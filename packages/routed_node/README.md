# routed_node

Multi-host JavaScript and edge runtime layer for **Routed**.

The package contains explicit runtime entrypoints for Node.js, Bun, Deno,
Cloudflare Workers, Vercel, and Netlify. It maps host-native requests and
responses into Routed's portable core boundary while preserving the same
`Engine`, router, middleware, controller, view, and handler code.

It is intentionally separate from **`routed_core`** and **`routed_io`**.

See [portable-host-architecture.md](../../docs/portable-host-architecture.md).

## Runtime entrypoints

| Runtime | Import | Entry model | Entry |
|---|---|---|---|
| Node.js | `package:routed_node/node.dart` | listener | `serveNode(...)` |
| Bun | `package:routed_node/bun.dart` | listener | `serveBun(...)` |
| Deno | `package:routed_node/deno.dart` | listener | `serveDeno(...)` |
| Cloudflare | `package:routed_node/cloudflare.dart` | Fetch export | `defineCloudflareFetch(...)` |
| Vercel | `package:routed_node/vercel.dart` | Fetch export | `defineVercelFetch(...)` |
| Netlify | `package:routed_node/netlify.dart` | Fetch export | `defineNetlifyFetch(...)` |

Listener runtimes support streaming and buffered dispatch. Fetch runtimes expose
native Fetch `Request`/`Response` bridges; streaming responses use a native
`ReadableStream`, while buffered dispatch remains available through the shared
portable exchange helpers.

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
  routed_core: ^0.3.3
  routed_node: ^0.1.0
```

The package uses `package:web` for JavaScript Fetch and stream bindings.

## Usage

```dart
import 'package:routed_node/node.dart';

final handle = await serveNode(engine, host: '0.0.0.0', port: 8080);
await handle.close();
```

Bun and Deno use the same application engine:

```dart
import 'package:routed_node/bun.dart';
// import 'package:routed_node/deno.dart';

final handle = await serveBun(engine, port: 3000);
await handle.close();
```

Fetch-export hosts install a JavaScript global entrypoint:

```dart
import 'package:routed_node/cloudflare.dart';

defineCloudflareFetch(engine);
```

The generated JS bootstrap calls `globalThis.__routed_fetch__` with the native
Fetch request. Vercel and Netlify use the equivalent `defineVercelFetch` and
`defineNetlifyFetch` entrypoints.

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

See [example/api/README.md](example/api/README.md).

## See also

- [`routed_io`](../routed_io) — `dart:io` host
- [`routed_core`](../routed_core) — engine + portable types
- [package-boundary-contract.md](../../docs/package-boundary-contract.md)
