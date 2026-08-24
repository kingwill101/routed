# routed_node

Multi-host JavaScript and edge runtime layer for **Routed**.

The package contains explicit runtime entrypoints for Node.js, Bun, Deno,
Cloudflare Workers, Vercel, and Netlify. It maps host-native requests and
responses into Routed's portable core boundary while preserving the same
`Engine`, router, middleware, controller, view, and handler code.

It is intentionally separate from **`routed_core`** and **`routed_io`**.

See the [portable host architecture guide](https://github.com/kingwill101/routed/blob/master/docs/portable-host-architecture.md).

## Runtime entrypoints

| Runtime | Import | Entry model | HTTP | Streaming | Native `Engine.ws(...)` | Verification |
|---|---|---|---:|---:|---:|---|
| Node.js | `package:routed_node/node.dart` | listener | ✅ | ✅ | ✅ | External HTTP + WebSocket echo |
| Bun | `package:routed_node/bun.dart` | listener | ✅ | ✅ | ✅ | Live HTTP + WebSocket echo |
| Deno | `package:routed_node/deno.dart` | listener | ✅ | ✅ | ✅ | Native `Deno.upgradeWebSocket` bridge implemented; live validation pending |
| Cloudflare Workers | `package:routed_node/cloudflare.dart` | Fetch export | ✅ | ✅ | ✅ | Live `/health` and `/ws` echo |
| Vercel | `package:routed_node/vercel.dart` | Fetch export | ✅ | ✅ | ❌ | Fetch bridge/contract coverage; no upgrade API |
| Netlify Edge | `package:routed_node/netlify.dart` | Fetch export | ✅ | ✅ | ❌ | Live HTTP; Edge Functions have no server-side upgrade boundary |

Legend: ✅ verified and supported, ⚠️ host may support WebSockets but Routed's
adapter is not implemented or not live-verified, ❌ unavailable through the
host entrypoint. Listener runtimes support streaming and buffered dispatch.
Fetch runtimes expose native Fetch `Request`/`Response` bridges; streaming
responses use a native `ReadableStream`.

## Core paths

| Path | API |
|---|---|
| Buffered Fetch edge | `dispatchFetchExchange` → `Engine.handlePortable` |
| Streaming Fetch edge | `dispatchFetchConnection` → `Engine.handleConnection` |
| Node value edge | `dispatchNodeExchange` → `Engine.handlePortable` |
| Node stream sink | `NodeHttpConnection` → `Engine.handleConnection` |

## Install

```yaml
dependencies:
  routed_core: ^0.5.0
  routed_node: ^0.2.0
```

The package internally uses `package:web` for JavaScript Fetch and stream
bindings; application code normally does not need to import it.

## Usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/node.dart';

Future<void> main() async {
  final engine = await Engine.create(providers: Engine.defaultProviders);
  final handle = await serveNode(engine, host: '0.0.0.0', port: 8080);
  await handle.close();
}
```

Bun and Deno use the same application engine:

```dart
import 'package:routed_node/bun.dart';
// import 'package:routed_node/deno.dart';

Future<void> main() async {
  final engine = await Engine.create(providers: Engine.defaultProviders);
  final handle = await serveBun(engine, port: 3000);
  await handle.close();
}
```

Fetch-export hosts install a JavaScript global entrypoint:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';

defineCloudflareFetchAsync(
  Engine.create(providers: Engine.defaultProviders),
);
```

When engine startup needs Worker bindings such as D1 or secrets, pass the
typed environment to the factory. The wrapper keeps `package:web` and JS
interop out of application code:

```dart
defineCloudflareFetchFactoryWithEnvironmentAsync((environment) async {
  final database = environment.d1('DB');
  // Build the engine and its typed providers from the binding.
  return Engine.create(providers: Engine.defaultProviders);
});
```

The generated JS bootstrap calls `globalThis.__routed_fetch__` with the native
Fetch request. Vercel and Netlify use the equivalent `defineVercelFetch` and
`defineNetlifyFetch` entrypoints.

Netlify Edge Functions support the Fetch bridge and streaming responses, but
Netlify does not expose a server-side WebSocket upgrade API to Edge Functions.
Accordingly, `netlifyCapabilities.webSocket` is intentionally `false`; use a
managed real-time service such as Ably or deploy the WebSocket route to Node or
Cloudflare instead. This is consistent with Netlify's serverless WebSocket
guidance, which uses Ably to host the persistent connection rather than keeping
one inside a Netlify function.

### Cloudflare bindings

`package:routed_node/cloudflare.dart` is the Cloudflare-specific entrypoint. It
exports the Fetch bootstrap plus wrappers for Worker environment bindings,
KV, D1, Durable Object namespaces/stubs, Durable Object storage, alarms, and
SQLite-backed Durable Object SQL. The host-neutral
`package:routed_node/routed_node.dart` entrypoint does not expose these APIs.

The supported Cloudflare binding set is D1, Durable Objects, Containers,
Workers (service bindings), R2, Workflows, Queues, and Secrets Store. All of
these APIs are value-oriented Dart contracts; application code does not need
to import `package:web` or `dart:js_interop`. KV and the Cache API remain
available as auxiliary bindings.

Use the environment and execution context attached to a Routed handler:

```dart
import 'package:routed_node/cloudflare.dart';

Future<void> recordRequest(ctx) async {
  final env = cloudflareEnvironmentOf(ctx);
  final execution = cloudflareExecutionContextOf(ctx);
  if (env == null || execution == null) return;

  final database = env.d1('DB');
  final result = await database
      .prepare('SELECT id, email FROM users WHERE id = ?')
      .bind([42])
      .first<Map<String, Object?>>();

  execution.waitUntil(writeAuditLog(result));
}
```

D1 values must be bound parameters. Sessions are available when a request
needs sequential consistency across D1 reads:

```dart
final session = env.d1('DB').withSession(bookmark: 'first-primary');
final rows = await session
    .prepare('SELECT id, email FROM users ORDER BY id')
    .all<Map<String, Object?>>();
final nextBookmark = await session.getBookmark();
```

Durable Object IDs and request stubs follow the current Workers namespace API:

```dart
final namespace = env.durableObjectNamespace('COUNTER');
final stub = namespace.getByName('global');
final request = cloudflareRequestOf(ctx);
if (request == null) return;
final response = await stub.fetch(request);

ctx.response.statusCode = response.status;
for (final entry in response.headers.entries) {
  ctx.response.setHeader(entry.key, entry.value);
}
if (response.body is List<int>) {
  ctx.response.writeBytes(response.body! as List<int>);
} else {
  ctx.response.write(response.body ?? '');
}
return ctx.response;
```

Buffered Durable Object responses also provide `response.text()` and
`response.json<T>()` helpers when the caller needs to inspect the payload before
returning it.

`cloudflareRequestOf(ctx)` returns a Routed-owned request wrapper. Its
`method`, `url`, `headers`, `text()`, and `json()` APIs do not require
`package:web` or `dart:js_interop`. The binding wrappers are only operational
in a JavaScript Worker;
the same public import remains analyzable on the Dart VM and reports an
`UnsupportedError` if a native binding is requested there.

When a request is not already available from a handler, construct one with the
same host-neutral API:

```dart
final request = createCloudflareRequest(
  'https://example.com/health',
  headers: {'accept': 'application/json'},
);
final response = await namespace.getByName('health').fetch(request);
```

Cloudflare's edge request metadata is available as a Dart map on incoming
requests. The keys vary by Cloudflare plan and feature, so the wrapper keeps
the values typed as Dart primitives and collections:

```dart
final request = cloudflareRequestOf(ctx);
final country = request?.cf['country'] as String?;
final colo = request?.cf['colo'] as String?;
```

The Cache API, R2, Queues, and Worker service bindings use the same public
entrypoint without exposing JavaScript interop:

```dart
final env = cloudflareEnvironmentOf(ctx);
if (env == null) return ctx.json({'error': 'cloudflare_unavailable'}, statusCode: 500);

final request = cloudflareRequestOf(ctx);
if (request == null) return ctx.json({'error': 'request_unavailable'}, statusCode: 500);

final edgeCache = await cloudflareCache();
final cached = await edgeCache.match(request);
if (cached != null) {
  ctx.response.statusCode = cached.status;
  for (final entry in cached.headers.entries) {
    ctx.response.setHeader(entry.key, entry.value);
  }
  if (cached.body is List<int>) {
    ctx.response.writeBytes(cached.body! as List<int>);
  } else {
    ctx.response.write(cached.body ?? '');
  }
  return ctx.response;
}

final userId = ctx.param('id')?.toString() ?? '';
final object = await env.r2('FILES').get('avatars/$userId.json');
final event = await env.queue('EVENTS').send(
  {'userId': userId, 'action': 'read'},
  contentType: CloudflareQueueContentType.json,
);
final serviceResponse = await env.service('PROFILE_API').fetch(request);
final greeting = await env.worker('PROFILE_API').call<String>('greet', ['Ada']);
```

R2 objects expose metadata and a Dart `Stream<List<int>>` body. Use
`readAsBytes()` or `readAsString()` for small objects, or consume `body`
directly for larger values. Queue sends return Cloudflare's post-send metrics;
`sendBatch` accepts `CloudflareQueueMessage` values. Configure these bindings
in Wrangler using the native `r2_buckets`, `queues`, and `services` sections.
The Routed CLI can generate those sections with `--r2`, `--queue`, and
`--service`.

Use the platform naming for Worker bindings with `env.worker(...)` when that
reads more clearly in application code. Worker bindings support both Fetch and
RPC methods:

```dart
final response = await env.worker('PROFILE_API').fetch(request);
```

Containers are addressed by a stable session ID. The request-facing API uses
the Container namespace binding and forwards to the Container's default port:

```dart
final instance = env.container('APP_CONTAINER').get('user-42');
final response = await instance.fetch(request);
```

Inside a Container-backed Durable Object, low-level lifecycle and process
controls are available through `state.container`:

```dart
final container = state.container;
if (container != null) {
  container.start();
  final process = await container.exec(['worker', '--version']);
  final output = await process.output();
  print(output.stdoutText);
}
```

Workflow bindings expose creation, status, pause/resume, restart, terminate,
and event delivery:

```dart
final workflow = env.workflow('BILLING');
final instance = await workflow.create(
  options: const CloudflareWorkflowCreateOptions(
    id: 'order-42',
    params: {'orderId': 42},
  ),
);
final status = await instance.status();
await instance.sendEvent(type: 'payment-received', payload: {'orderId': 42});
```

Secrets Store values are read asynchronously from the Worker binding. Keep
the value in memory only as long as needed and never return it in a response
or log it:

```dart
final apiKey = await env.secretsStore('PAYMENTS_API_KEY').get();
if (apiKey == null) {
  return CloudflareResponse.text('Secret unavailable', status: 503);
}
```

Secrets Store management remains a Cloudflare account operation. The Worker
runtime binding is intentionally the only Routed API that reads the value.

### Complete Worker example

A typical application reads D1 and KV from a normal Routed handler, and uses a
Durable Object for state that must be coordinated by one object instance:

```dart
import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';

Engine createEngine() {
  final engine = Engine(providers: Engine.defaultProviders);

  engine.get('/users/{id}', (ctx) async {
    final env = cloudflareEnvironmentOf(ctx);
    if (env == null) {
      return ctx.json({'error': 'cloudflare_bindings_unavailable'}, statusCode: 500);
    }

    final id = ctx.param('id')?.toString() ?? '';
    final cache = env.kv('CACHE');
    final cached = await cache.getJson<Map<String, Object?>>('user:$id');
    if (cached != null) return ctx.json(cached);

    final user = await env
        .d1('DB')
        .prepare('SELECT id, email FROM users WHERE id = ?')
        .bind([id])
        .first<Map<String, Object?>>();
    if (user == null) return ctx.json({'error': 'not_found'}, statusCode: 404);

    // Do not hold up the response for cache maintenance.
    cloudflareExecutionContextOf(ctx)?.waitUntil(
      cache.put('user:$id', jsonEncode(user)),
    );
    return ctx.json(user);
  });

  return engine;
}
```

The Durable Object itself receives Cloudflare request and state wrappers. New
objects should use SQLite-backed storage:

```dart
import 'package:routed_node/cloudflare.dart';

final class Counter extends CloudflareDurableObject {
  Counter(super.state, super.env) {
    final sql = state.storage.sql;
    if (sql != null) {
      state.blockConcurrencyWhile(() async {
        sql.exec('''
          CREATE TABLE IF NOT EXISTS counter (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            value INTEGER NOT NULL
          )
        ''');
        sql.exec(
          'INSERT OR IGNORE INTO counter (id, value) VALUES (1, 0)',
        );
      });
    }
  }

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    final sql = state.storage.sql;
    if (sql == null) {
      return CloudflareResponse.text(
        'Counter requires SQLite-backed Durable Object storage.',
        status: 500,
      );
    }

    final current =
        (sql.exec('SELECT value FROM counter WHERE id = 1').one()['value']
                as num?)
            ?.toInt() ??
        0;
    final next = current + 1;
    sql.exec(
      'UPDATE counter SET value = ? WHERE id = 1',
      [next],
    );
    return CloudflareResponse.json({'value': next});
  }
}
```

Register the class in the Dart Worker entrypoint and bind it in Wrangler:

```dart
void main() {
  defineCloudflareDurableObjects({'Counter': Counter.new});
  defineCloudflareFetchFactoryAsync(createEngine);
}
```

When using `routed_cli`, the same registration and module exports are generated
for you:

```bash
routed deploy --target cloudflare \
  --durable-object COUNTER=Counter \
  --d1 DB=app:YOUR_DATABASE_ID \
  --r2 FILES=app-files \
  --queue EVENTS=app-events \
  --service PROFILE_API=profile-api
```

The D1 value uses the form `BINDING=DATABASE_NAME:DATABASE_ID`; both database
fields are required by Wrangler. The R2, Queue, and service values use
`BINDING=RESOURCE_NAME` and are emitted as `r2_buckets`, Queue producers, and
`services` entries in the generated Wrangler config. Containers use
`BINDING=CLASS_NAME|IMAGE|PORT|MAX_INSTANCES`, Workflows use
`BINDING=WORKFLOW_NAME:CLASS_NAME[:SCRIPT_NAME]`, and Secrets Store uses
`BINDING=STORE_ID:SECRET_NAME`.

```jsonc
{
  "durable_objects": {
    "bindings": [
      { "name": "COUNTER", "class_name": "Counter" }
    ]
  },
  "d1_databases": [
    { "binding": "DB", "database_name": "app", "database_id": "..." }
  ],
  "kv_namespaces": [
    { "binding": "CACHE", "id": "..." }
  ],
  "r2_buckets": [
    { "binding": "FILES", "bucket_name": "app-files" }
  ],
  "queues": {
    "producers": [
      { "binding": "EVENTS", "queue": "app-events" }
    ]
  },
  "services": [
    { "binding": "PROFILE_API", "service": "profile-api" }
  ],
  "migrations": [
    { "tag": "routed-v1", "new_sqlite_classes": ["Counter"] }
  ]
}
```

`Counter` must be exported by the final Worker module under the same class name
used in `class_name`. `routed_cli` generates that named export and wires it
into the Worker module, so application code does not need to write a
JavaScript wrapper. The generated export forwards `fetch`, `alarm`, and the
Durable Object hibernation callbacks.

### Durable Object WebSockets

Durable Object WebSockets use Cloudflare's hibernation API through typed
Routed-owned wrappers. The application only sees `CloudflareWebSocket` and
`CloudflareWebSocketPair`; it does not import `package:web` or
`dart:js_interop`:

```dart
final class ChatRoom extends CloudflareDurableObject {
  ChatRoom(super.state, super.env);

  @override
  CloudflareResponse fetch(CloudflareRequest request) {
    if (request.headers['upgrade']?.toLowerCase() != 'websocket') {
      return CloudflareResponse.text(
        'WebSocket upgrade required.',
        status: 426,
      );
    }

    final pair = cloudflareWebSocketPair();
    state.acceptWebSocket(pair.server, tags: const ['chat']);
    return pair.response;
  }

  @override
  void webSocketMessage(CloudflareWebSocket socket, Object message) {
    for (final peer in state.getWebSockets(tag: 'chat')) {
      peer.send(message);
    }
  }

  @override
  void webSocketClose(
    CloudflareWebSocket socket,
    int code,
    String reason,
    bool wasClean,
  ) {
    // Persist anything needed for the next wake-up using
    // socket.serializeAttachment or state.storage.
  }
}
```

Use `socket.send('text')` or `socket.send(Uint8List)` for messages, and
`serializeAttachment`/`deserializeAttachment` for connection metadata that
must survive hibernation. `webSocketError` is available for runtime error
notifications.

The Dart VM intentionally uses **`package:routed_io`** for process hosting.
JavaScript-only listener and Fetch entrypoints throw a clear
`UnsupportedError` when invoked on the VM.

## Capabilities and extensions

Every runtime exposes a `RoutedNodeCapabilities` value. Check the entry model
and feature flags before using host-specific APIs:

```dart
import 'package:routed_node/cloudflare.dart';

if (cloudflareCapabilities.streaming) {
  // Native ReadableStream responses are available.
}
```

Host extensions are available from a handler context when a native host object
is present:

```dart
final extension = routedNodeExtensionOf<FetchRuntimeExtension>(ctx);
```

Lifecycle phases are published through Routed's existing `EventManager`, so
applications can observe boot, ready, request, failure, shutdown, and stop
without a second lifecycle system.

## Testing

```bash
cd packages/routed_node
dart test -p vm
dart compile js example/api/bin/server.dart -o /tmp/routed_node.js -O1
```

VM tests use host-neutral fakes. JavaScript compilation and host integration
smoke tests run only on the corresponding runtime.

## Sample API project

Runnable JSON API under **`example/api/`**:

```bash
cd packages/routed_node/example/api
dart pub get
dart run bin/smoke.dart
# npm run build && npm start  # Node ≥22 host
```

See the [sample API README](https://github.com/kingwill101/routed/blob/master/packages/routed_node/example/api/README.md).

## See also

- [`routed_io`](https://github.com/kingwill101/routed/tree/master/packages/routed_io) — `dart:io` host
- [`routed_core`](https://github.com/kingwill101/routed/tree/master/packages/routed_core) — engine + portable types
- [Package boundary contract](https://github.com/kingwill101/routed/blob/master/docs/package-boundary-contract.md)
