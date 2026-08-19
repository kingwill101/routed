# Node/JavaScript Runtime Catalog

This catalog records the useful design signals from the local `third_party`
repositories. They are reference material, not dependencies or source to copy.

## Sources

| Source | Snapshot | Status | Best use |
|---|---:|---|---|
| `third_party/dart_edge` | `97d01ba` | Archived/unmaintained | Historical edge bindings and CLI/deployment ideas |
| `third_party/osrv` | `0c7c77c` | Active reference snapshot | Runtime boundaries, capabilities, WebSocket lifecycle, black-box tests |

## Dart Edge

`dart_edge` is an archived experimental edge-functions project. It targets
Cloudflare Workers, Vercel Edge Functions, and Supabase Edge Functions, with
Netlify and Deno Deploy listed as possible future targets.

### Structure

- `packages/edge`: CLI, project bricks, compiler, dev server, and platform
  build commands.
- `packages/edge_runtime`: Web API-shaped bindings for `Request`, `Response`,
  `Headers`, streams, crypto, blobs, form data, and cache.
- `packages/cloudflare_workers`: Cloudflare-specific bindings including KV,
  Durable Objects, HTMLRewriter, execution context, and sockets.
- `packages/vercel_edge`, `packages/netlify_edge`, `packages/deno_deploy`, and
  `packages/supabase_functions`: platform entrypoints and bindings.
- `bricks/`: generated project templates for Cloudflare, Vercel, and Supabase.
- `docs/` and `examples/`: platform setup and API usage.

### Useful lessons

1. Keep standard Web API bindings separate from platform-specific bindings.
2. Put compilation, generated shims, templates, and deployment configuration in
   a host CLI rather than in application code.
3. Treat edge APIs as a deliberate subset of normal server APIs.
4. Generated JavaScript wrappers should remain small and visible.

### Important limitations

- The repository itself warns that it is archived because of DX, stability,
  testing, and compilation-time problems.
- The compiler always uses `--server-mode`, which is appropriate for some
  standalone JavaScript hosts but is not a safe default for Worker-style
  fetch exports.
- Several bindings are incomplete or stubs, especially lower-level Deno APIs.

### Direction for Routed

Use `dart_edge` as historical evidence for a separate platform-binding layer
and generated deployment workflow. Routed now exposes the supported Cloudflare
binding surface from `package:routed_node/cloudflare.dart`, using current
Workers D1, Durable Object, Container, R2, Queue, Worker service, Workflow,
and Secrets Store APIs while retaining VM-safe conditional implementations.
The public request/response and Durable Object hibernation
WebSocket boundaries are Routed-owned, so applications do not need
`package:web` or `dart:js_interop`; the deployment CLI generates Durable Object
class exports and forwards their lifecycle callbacks. Do not use `dart_edge` as the
architectural base for `routed_node`, and do not copy its bindings or compiler
assumptions.

## osrv

`osrv` is the closest architectural reference. It deliberately provides a
runtime layer rather than a router or middleware framework.

### Core contract

- `Server.fetch(Request, RequestContext) -> Response`
- optional `onStart`, `onStop`, and `onError` hooks
- explicit runtime entrypoints
- `RuntimeCapabilities` for host truth
- typed `RuntimeExtension` escape hatches
- separate listener and fetch-export entry models

The public WebSocket surface is request-scoped:

```dart
final response = context.webSocket?.accept(handler, protocol: 'chat');
return response ?? Response.text('normal HTTP');
```

Acceptance is an explicit response-compatible outcome. Runtime adapters consume
that outcome using their native upgrade model.

### Runtime matrix from osrv

| Runtime | Entry model | HTTP/streaming | WebSocket | Native shape |
|---|---|---:|---:|---|
| Dart | listener | yes | yes | `WebSocketTransformer.upgrade` |
| Node | listener | yes | yes | HTTP `upgrade` event + raw frame adapter |
| Bun | listener | yes | yes | `server.upgrade(request)` + server callbacks |
| Deno | listener | yes | host-dependent | `Deno.upgradeWebSocket(request)` |
| Cloudflare | fetch export | yes | yes | `WebSocketPair` + native `101` response |
| Vercel | fetch export | yes | no | no supported server upgrade path |
| Netlify | fetch export | yes | no | managed real-time service required |

The matrix matches Routed's current direction closely, with one key API
choice: osrv's WebSocket acceptance is a response outcome, while Routed keeps
`Engine.ws(path, handler)` and dispatches through the core engine. Those choices
can coexist: Routed's host layer can continue adapting native sockets while
its core route registration remains authoritative.

### Runtime bridge patterns worth adopting

#### Bun

`osrv` has the clearest Bun design:

1. Allocate a monotonically increasing request token.
2. Store the accepted handler in `pendingUpgrades[token]`.
3. Call `server.upgrade(request, {data: token})`.
4. Return no HTTP response when the upgrade succeeds.
5. Resolve the token in the server-level `open`, `message`, `close`, and
   `error` callbacks.
6. Move accepted sessions into `activeSockets`.
7. Track sessions in a shutdown coordinator.
8. Close active sockets with `1001` during runtime shutdown.

This is stronger than a bridge that only maps a socket object after the fact:
it handles the gap between the fetch callback and Bun's later `open` event,
and it makes shutdown and rejected upgrades explicit.

#### Deno

`osrv` treats Deno as a fetch-style upgrade even though it owns a listener:

1. Run the application request pipeline first.
2. If the application returned an accepted upgrade outcome, call
   `Deno.upgradeWebSocket(request)`.
3. Adapt the returned `socket` to the shared WebSocket contract.
4. Return the returned native `response`.
5. Track the session and await its `opened` state before invoking the handler.

This avoids pretending Deno has Node's raw upgrade event and keeps the native
response/socket pair together.

#### Node

`osrv` validates the full boundary around Node upgrades:

- startup failures produce `503` responses;
- missing or invalid upgrade headers produce `400`;
- requested and selected subprotocols are validated;
- raw `101` responses are rejected unless created by the WebSocket request API;
- active sockets are tracked and closed during shutdown;
- frame limits, masking, fragmentation, control frames, UTF-8, and close codes
  are handled explicitly.

Routed's raw Node framing adapter should converge on these behavioral tests,
even if its internal types remain different.

#### Cloudflare

`osrv` uses typed `WebSocketPair` properties (`0` client, `1` server), calls
`server.accept()`, and constructs a native `Response` with the accepted client
socket. It also handles text, bytes, close, error, protocol selection, and
peer-close acknowledgement.

#### Fetch entrypoints

`osrv` uses a lazy/start-on-first-request entry handler and a separate startup
operation. That is relevant to the Cloudflare hang we fixed: unresolved
initialization Futures must be attached to a request rather than created as
unowned top-level work.

### Testing model worth adopting

The strongest part of `osrv` is its test layout:

- portable tests under `test/`;
- compile-target tests;
- preflight/probe tests for Bun and Deno;
- black-box process tests for Node, Bun, and Deno;
- Worker-host tests for Cloudflare;
- fetch-export tests for Vercel and Netlify;
- shared runtime contract helpers;
- protocol tests for masking, fragmentation, invalid UTF-8, close frames,
  protocol errors, shutdown races, and response sanitization.

Routed currently has good core, Node, Bun, and Cloudflare coverage, but should
add the same separation and shared contract fixtures for Deno and for each
fetch-export host.

## Comparison with routed_node

| Concern | `routed_node` today | Recommended direction |
|---|---|---|
| Application contract | Routed `Engine` and route pipeline | Keep; it is the framework layer |
| Host boundary | `FetchRequestView`, adapters, runtime extensions | Keep and make adapters more typed |
| WebSocket registration | `Engine.ws(path, handler)` | Keep; runtime layer must not become a router |
| Bun bridge | Implemented and live echo verified | Add pending/active session tracking and shutdown semantics |
| Deno bridge | Implemented from native upgrade contract | Add live process validation and session tracking |
| Node transport | Raw upgrade and frame parser | Expand protocol/error/shutdown contract tests |
| Cloudflare | `WebSocketPair` and lazy Fetch engine | Add protocol/close/session tests |
| Capabilities | Static per-runtime booleans | Keep static baseline; optionally add runtime probe diagnostics |
| Deployment | Routed CLI generates shims and config | Keep; split compiler policy by listener vs fetch export |
| Lifecycle | Routed `EventManager` lifecycle events | Keep; add active WebSocket resource accounting |
| Core portability | Transitional adapter bridge remains | Continue shrinking synthetic `HttpRequest` usage |

## Recommended roadmap

### 1. Stabilize a host bridge contract

Introduce internal host-bridge expectations, without exposing an adapter registry:

- request conversion;
- response conversion;
- WebSocket upgrade preparation;
- WebSocket session conversion;
- lifecycle/resource tracking;
- capability declaration.

Each runtime can implement these separately. The shared contract should describe
behavior, not force identical native APIs.

### 2. Create a shared runtime contract fixture

Add a reusable test fixture for:

- `/health` and capability reporting;
- ordinary GET/POST/body/headers;
- streaming response;
- WebSocket upgrade and echo;
- selected subprotocol;
- rejected path and rejected handshake;
- peer close and application close;
- malformed/protocol-error teardown where observable;
- shutdown with an active socket.

Run the fixture against Node, Bun, Deno, and Cloudflare where the host permits.
Keep Vercel and Netlify tests explicit about unsupported upgrades.

### 3. Improve Bun resource semantics

The current Bun bridge proves the happy path, but should adopt the osrv model:

- token state must be removed on every rejection/error/close;
- accepted sessions must be tracked by the server handle;
- `JsServerHandle.close()` should initiate WebSocket shutdown and await active
  sessions;
- callbacks should preserve close code/reason where Bun exposes them;
- add binary and shutdown-race tests.

### 4. Complete Deno validation

Install or provision a real Deno CLI in CI, then validate:

- HTTP and streaming;
- `Deno.upgradeWebSocket` handshake;
- `ready` and echo messages;
- binary messages;
- close behavior;
- shutdown behavior;
- capability output.

Do not mark Deno as fully verified based only on compilation.

### 5. Split compiler policy by host family

Use separate build profiles:

- Node/Bun/Deno listeners: standalone JS build, server liveness handling as
  required by the host;
- Cloudflare/Vercel/Netlify fetch exports: no `--server-mode`, native host shim,
  lazy request-scoped initialization;
- preserve source maps and a deterministic generated staging directory.

This addresses the historical `dart_edge` compiler assumption and the Node
preamble issue without making Worker builds inherit listener behavior.

### 6. Add host capability diagnostics

Keep the simple public capability booleans, but expose internal diagnostics for
support claims:

- host family;
- adapter implemented;
- live probe passed;
- capability unavailable reason;
- verification timestamp/build revision.

This prevents a runtime from advertising WebSocket support merely because the
underlying JavaScript host happens to expose a WebSocket API.

## Decision Summary

- **Use `osrv` as the primary design reference** for runtime boundaries,
  capabilities, typed extensions, WebSocket outcomes, and black-box testing.
- **Use `dart_edge` as historical context only** for edge bindings, project
  bricks, and deployment CLI ideas.
- **Keep Routed's framework boundary**: `Engine`, routing, middleware, and
  `Engine.ws(...)` remain in Routed; host packages only translate native I/O.
- **Next implementation priority**: harden Bun session lifecycle, add live Deno
  integration, and introduce a shared cross-runtime contract test suite.
