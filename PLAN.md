# Plan: Multi-host `routed_node` runtime layer

## Context

`routed_node` currently provides Node.js `http.createServer` support for Routed,
while `routed_core` already contains the portable boundary needed to support
non-`dart:io` hosts:

- `PortableRequest` / `PortableResponse`
- `RequestAdapter` / `ResponseAdapter`
- `Engine.handlePortable(...)`
- `Engine.handleConnection(...)`
- `ServerTransport` / `ServerHandle`
- `HostCapabilities`

The goal is to expand the single `routed_node` package into an `osrv`-style
multi-host package while preserving Routed's application model: `Engine`,
`Router`, middleware, providers, controllers, views, and handlers should not
change when the deployment host changes.

The package will contain all JavaScript/edge host integrations, but each host
will have an explicit entrypoint and only expose its own host APIs. Listener
hosts and fetch-export hosts must remain distinct models.

## Confirmed decisions

- **All six hosts are in the first milestone:** Node, Bun, Deno, Cloudflare,
  Vercel, and Netlify.
- **Separate public imports are required:** use files such as
  `package:routed_node/node.dart`, `bun.dart`, `deno.dart`,
  `cloudflare.dart`, `vercel.dart`, and `netlify.dart`.
- **Lifecycle integration uses Routed's existing `EventManager`:** do not
  introduce a parallel `onStart`/`onStop` callback contract in `routed_node`.
  Host boot and shutdown events must be represented through existing Routed
  events, with new event types added only where the current event model has a
  real gap.
- **Both buffered and streaming paths are required:** listener hosts must
  support streaming adapters and value-style portable dispatch where the host
  permits it; Fetch hosts must provide buffered `Response` construction and
  streaming `Response` construction where the platform supports streams.
- **Typed native host extensions are required immediately.** These remain in
  `routed_node` and are exposed through request/context-scoped access without
  leaking host types into `routed_core`.
- **WebSocket support is required for every host where the host API supports
  it.** Unsupported hosts must report the capability accurately and provide a
  deterministic unsupported-upgrade behavior.
- **`routed_node` may break compatibility:** this package is unused, so its
  current public API and internal layout may be replaced rather than preserved.
  The new multi-host API should be designed cleanly instead of carrying legacy
  Node-only constraints.
- **Host bootstrap artifacts are included:** each host needs a documented
  bootstrap/deployment example; generated shims are added only when required
  by the host's JS interop model.

## Initial host matrix

| Host | Entry model | Initial entrypoint | Main bridge |
|---|---|---|---|
| Node.js | listener | `serveNode(...)` | Node `http` |
| Bun | listener | `serveBun(...)` | `Bun.serve` |
| Deno | listener | `serveDeno(...)` | `Deno.serve` |
| Cloudflare Workers | fetch export | `defineCloudflareFetch(...)` | Fetch `Request`/`Response` |
| Vercel | fetch/function export | `defineVercelFetch(...)` | Fetch/function request |
| Netlify | fetch/function export | `defineNetlifyFetch(...)` | Fetch/function request |

Dart VM hosting remains in `routed_io`.

## Approach

1. Stabilize a shared runtime contract inside `routed_node` for runtime identity,
   entry model, capabilities, native extension access, and host request scope.
2. Reuse Routed's existing `EventManager` for host lifecycle integration. Add
   typed host lifecycle events only when startup, ready, error, drain, and stop
   cannot be represented by existing request/config/runtime events.
3. Reuse the current Node adapter implementation where useful, but redesign
   the public API around the final multi-host contract rather than preserving
   the unused Node-only API.
4. Add shared Fetch-to-Routed conversion utilities for edge/function hosts.
5. Add host-specific runtime modules under `routed_node` with explicit public
   imports such as `package:routed_node/bun.dart` and
   `package:routed_node/cloudflare.dart`.
6. Route all hosts through the existing portable core path. Use the streaming
   adapter path where the host supports it; use `Engine.handlePortable(...)`
   where the host expects a value-style Fetch response.
7. Report capabilities honestly rather than presenting all hosts as equivalent.
8. Add host contract tests using pure-Dart fakes, plus compile/runtime tests for
   JS hosts where the environment supports them.
9. Update the portable-host architecture, package-boundary documentation, and
   `routed_node` README with the runtime matrix and deployment examples.

## Resolved planning decisions

- All six hosts are in the first milestone.
- Each host has a separate public import file.
- Lifecycle integration uses Routed's existing `EventManager`, not a parallel
  callback bus.
- Listener and Fetch hosts must support both streaming and buffered response
  paths wherever the platform permits them.
- Typed native host extensions are part of the first milestone.
- WebSockets are implemented wherever the host supports them; unsupported hosts
  report that capability and fail upgrades deterministically.
- Host bootstrap examples and required shims are included.
- `routed_node` is unused and may be redesigned without backward compatibility.
  Existing `serveNode`, `dispatchNodeExchange`, and adapter names are not API
  constraints.

Remaining implementation choices are technical details for the OpenSpec design
review: conditional JS interop versus host-view fakes, the exact lifecycle event
class shape, and whether edge entrypoints return native responses directly or
also expose neutral conversion helpers.

## Files to modify

### Core compatibility surface

- `packages/routed_core/lib/src/http/portable_message.dart`
- `packages/routed_core/lib/src/http/transport.dart`
- `packages/routed_core/lib/src/engine/engine.dart` (only where the portable
  lifecycle contract needs a narrowly-scoped compatibility adjustment)
- `packages/routed_core/lib/routed_core.dart`
- `packages/routed_core/lib/src/events/` if host lifecycle events need to be
  added to the existing EventManager vocabulary

### `routed_node`

- `packages/routed_node/lib/routed_node.dart`
- New public entrypoints: `node.dart`, `bun.dart`, `deno.dart`,
  `cloudflare.dart`, `vercel.dart`, and `netlify.dart`
- `packages/routed_node/pubspec.yaml`
- Existing Node files under `packages/routed_node/lib/src/`
- New shared runtime/capability files under
  `packages/routed_node/lib/src/runtime/` or `shared/`
- New host modules for Bun, Deno, Cloudflare, Vercel, and Netlify
- `packages/routed_node/test/`
- `packages/routed_node/example/`
- `packages/routed_node/README.md`
- `packages/routed_node/CHANGELOG.md`

### Documentation

- `docs/portable-host-architecture.md`
- `docs/package-boundary-contract.md`
- New runtime compatibility documentation under `docs/docs/routed/`
- `packages/routed_node/example/api/README.md`

### Specification/planning artifacts

- OpenSpec proposal, design, tasks, and capability deltas after the remaining
  product decisions are confirmed.

## Reuse

- Reuse `PortableRequest`, `PortableResponse`, and `HostCapabilities` from
  `routed_core` instead of introducing a second request contract.
- Reuse `Engine.handlePortable(...)` for Fetch-style hosts.
- Reuse `RequestAdapter` / `ResponseAdapter` and `HttpConnection` for streaming
  listener hosts.
- Reuse `ServerTransport` / `ServerHandle` for Node, Bun, and Deno listeners.
- Reuse `NodeIncomingView` / `NodeServerResponseView` as the testing pattern for
  host-native views.
- Reuse `EventManager` and existing Routed request/config/runtime events for
  lifecycle observability; do not create a second lifecycle bus.
- Reuse current Node adapter code where useful, but do not preserve
  `serveNode(...)`, `dispatchNodeExchange(...)`, or adapter names as
  compatibility requirements.
- Follow the explicit runtime-entry and capability model demonstrated by
  `medz/osrv`, without copying its public API or implementation.

## Proposed public entrypoints

Listener hosts:

```dart
import 'package:routed_node/node.dart';
import 'package:routed_node/bun.dart';
import 'package:routed_node/deno.dart';

final nodeHandle = await serveNode(engine, host: '0.0.0.0', port: 8080);
final bunHandle = await serveBun(engine, port: 3000);
final denoHandle = await serveDeno(engine, port: 8000);
```

Fetch-export hosts:

```dart
import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/vercel.dart';
import 'package:routed_node/netlify.dart';

void main() {
  defineCloudflareFetch(engine);
  // or defineVercelFetch(engine) / defineNetlifyFetch(engine)
}
```

The exact host-native function signatures will be finalized in the design
artifact, but the import separation and listener-versus-fetch distinction are
fixed requirements.

## Runtime contract

The shared contract belongs in `routed_node` and is intentionally separate from
Routed's application request model:

```dart
enum RoutedNodeEntryModel { listener, fetchExport }

enum RoutedNodeRuntime {
  node,
  bun,
  deno,
  cloudflare,
  vercel,
  netlify,
}

final class RoutedNodeCapabilities {
  const RoutedNodeCapabilities({
    required this.runtime,
    required this.entryModel,
    required this.streaming,
    required this.bufferedResponses,
    required this.webSocket,
    required this.fileSystem,
    required this.backgroundWork,
  });

  final RoutedNodeRuntime runtime;
  final RoutedNodeEntryModel entryModel;
  final bool streaming;
  final bool bufferedResponses;
  final bool webSocket;
  final bool fileSystem;
  final bool backgroundWork;
}
```

The exact names may change during the OpenSpec review, but the contract must
make entry model and capability differences observable before host-specific
operations are attempted.

## Native host extensions

Host extensions must be typed and host-owned:

- `NodeRuntimeExtension` exposes Node request/response/server handles.
- `BunRuntimeExtension` exposes Bun request/server handles.
- `DenoRuntimeExtension` exposes Deno request/server handles.
- `CloudflareRuntimeExtension` exposes the Workers request and execution
  context/environment where available.
- `VercelRuntimeExtension` exposes the function request/context where available.
- `NetlifyRuntimeExtension` exposes the function request/context and
  `waitUntil` integration where available.

The common core must never import or type-reference these host objects.
Extensions should be available through a request-scoped host context or a
well-defined `RoutedNodeContext` attached by the host adapter.

## Lifecycle integration

Host packages will publish lifecycle events through the engine's existing
`EventManager` rather than adding an independent callback API. The event model
must cover, at minimum:

- host boot requested
- host ready/listening or fetch export installed
- host request accepted/started
- host request completed
- host request failed
- host shutdown requested
- host stopped

Request lifecycle events already exist in `routed_core`; the implementation
should reuse them rather than duplicate them. Host lifecycle events should carry
runtime, entry model, capabilities, and host extension/context data without
making the events depend on host-specific types in core.

## Host behavior matrix

| Host | Streaming | Buffered | WebSocket | Filesystem | Background work | Notes |
|---|---:|---:|---:|---:|---:|---|
| Node | yes | yes | yes | yes | yes | `node:http`, native host extension |
| Bun | yes | yes | yes | yes | yes | `Bun.serve`, upgrade through Bun server API |
| Deno | yes | yes | host-dependent | yes | yes | `Deno.serve`, upgrade only when supported |
| Cloudflare | yes | yes | yes | no | yes | Fetch `Response`, `ExecutionContext.waitUntil` |
| Vercel | yes | yes | no/host-dependent | yes | yes | function/fetch adapter, deployment-dependent extensions |
| Netlify | yes | yes | no/host-dependent | yes | request-dependent | function/fetch adapter, `waitUntil` when exposed |

The matrix is a declared capability baseline, not a promise that every host has
identical protocol details.

## Verification

- `dart analyze packages/routed_core packages/routed_node`
- `dart test packages/routed_node/test`
- Pure-Dart adapter tests for every host contract
- JS/Node compile and runtime smoke tests for Node/Bun/Deno entries
- Fetch export tests for edge hosts using host-native request fakes or JS tests
- Parity checks for route matching, middleware, headers, cookies, bodies,
  status codes, errors, streaming claims, and capability reporting
- Lifecycle event tests proving EventManager receives host start/ready/request/
  stop/failure events
- Documentation build and link validation
- OpenSpec strict validation before implementation approval
