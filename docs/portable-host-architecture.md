# Portable Host Architecture

Design note for multi-host Routed (Dart VM, Node.js, Workers, …).

Inspired by the *shape* of multi-runtime Dart servers (portable messages at the
edge, host packages only at the boundary)—not by any third-party source.

## Goals

1. **One app pipeline** for routing, middleware, DI, and handlers.
2. **Host packages own I/O** (`routed_io`, `routed_node`, future workers).
3. **No host types in the long-term core contract** (no `HttpRequest`, no
   Node `IncomingMessage` in engine APIs).
4. **Explicit runtime selection** — apps import the host they deploy to.
5. **Honest capabilities** — hosts declare what they support; core does not
   fake parity (e.g. websockets on every platform).

## Non-goals

- Auto-detecting “which host am I on?”
- One universal config object for every platform
- Copying third-party APIs, types, or implementation code
- Full rewrite of existing handler/`EngineContext` APIs in one step

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│  App handlers  (EngineContext, middleware, providers)       │
├─────────────────────────────────────────────────────────────┤
│  routed_core                                                │
│    PortableRequest / PortableResponse  (value messages)     │
│    RequestAdapter / ResponseAdapter    (stream sink edge)   │
│    Engine.handlePortable / handleConnection                 │
├──────────────┬──────────────────┬───────────────────────────┤
│  routed_io   │  routed_node multi-host runtime             │
│  dart:io     │  Node/Bun/Deno/Fetch host bridges           │
└──────────────┴──────────────────┴───────────────────────────┘
```

| Layer | Owns |
|-------|------|
| **Core** | Routing, middleware chain, config, DI, portable message types |
| **Host package** | Bind/listen or fetch export; map host types ↔ portable messages; declare capabilities |
| **App** | Routes and business logic; depends on core + one host package |

## Two edge shapes

### 1. Connection (stream sink) — `handleConnection`

```text
host → RequestAdapter + ResponseAdapter → Engine.handleConnection
                                         → writes into ResponseAdapter
```

Used by long-lived listeners and Fetch hosts that want progressive
write/close through a native stream. `routed_io` and `routed_node` use this path
where the host supports it.

### 2. Message (value in / value out) — `handlePortable`

```text
host → PortableRequest → Engine.handlePortable → PortableResponse → host
```

Preferred for fetch-style hosts (Workers) and for hosts that can buffer a
response. Internally, core still runs the existing pipeline via a recording
sink until the pipeline is fully portable (no synthetic `HttpRequest`).

## Host entry models

| Model | Hosts | Entry |
|-------|-------|--------|
| **Serve** | VM (`routed_io`), Node/Bun/Deno (`routed_node`) | `serve*(engine, host, port)` |
| **Fetch export** | Cloudflare, Vercel, Netlify (`routed_node`) | Host invokes a Fetch export backed by `handlePortable` / `handleConnection` |

Do not collapse these into one fake API. Serve returns a `ServerHandle`; fetch
export has no long-lived listener handle.

## Capabilities

Hosts (or runtimes) should expose a small capability snapshot, for example:

- streaming response bodies
- websocket upgrade
- filesystem
- background work after the response

Core and middleware branch on **declared** capabilities instead of catching
`UnsupportedError` deep in platform code.

```dart
// Sketch — see HostCapabilities in routed_core
class HostCapabilities {
  const HostCapabilities({
    this.streaming = true,
    this.websocket = false,
    this.fileSystem = false,
  });
  final bool streaming;
  final bool websocket;
  final bool fileSystem;
}
```

## Escape hatches

Optional host-only access (Node process, raw `HttpRequest`) stays **outside**
the portable message types—on the host package or via a narrow extension object
on the connection. Portable messages never carry host handles.

`NativeRequestHandle` remains a **transitional fast path** for `dart:io` only.

## Migration steps

1. **Done:** `RequestAdapter` / `ResponseAdapter`, `HttpConnection`,
   `AdapterHttpBridge`, `routed_io`, and the initial Node transport.
2. **Done:** `routed_node` runtime/capability contracts, native Fetch bridge,
   and explicit Node/Bun/Deno/Cloudflare/Vercel/Netlify entrypoints.
3. **Done:** `PortableRequest` / `PortableResponse` / `HostCapabilities` and
   `Engine.handlePortable` (recording sink over the existing pipeline).
4. **Done:** Node and IO hosts map through portable messages at the edge
   (`dispatchNodeExchange`, `dispatchIoExchange`); IO serve keeps a native
   fast path by default (`portableEdge: false`).
5. **In progress:** shrink residual `dart:io` in core (see below).
6. **Later:** pipeline consumes portable types natively; drop
   `AdapterHttpBridge`; optional fetch-export host package for Workers.

## Residual `dart:io` in `routed_core` (shrink list)

| Area | Status |
|------|--------|
| `Request` / `Response` | **Dual-mode:** native IO **or** `fromAdapter` / portable |
| Route constraints | **`ConstraintRequestView`** — domain/params without full IO |
| `Engine.handlePortable` | Value edge via recording adapter + bridge |
| `AdapterHttpBridge` | Still used for portable → existing `handleRequest` pipeline |
| `Engine.handleRequest` | Primary IO pipeline entry |
| WebSocket upgrade | Still `WebSocketTransformer` + IO types |
| `Engine.serve` / `serveSecure` | Legacy bind; prefer host packages |
| Security helpers | Some IP/`InternetAddress` usage |
| Process env | **Fixed:** `readProcessEnvironment` (VM + Node) |
| Adapter bridge addresses | **Fixed:** null `connectionInfo` when `InternetAddress` unsupported |

`dart test -p node` works for `routed_node` adapter + Engine portable path
tests. Next shrink: matched routes on dual-mode types without synthetic
`HttpRequest` (`AdapterHttpBridge` exit).

## Package rules

```
routed_core   → no Node/Workers APIs; shrink dart:io surface over time
routed_io     → dart:io only; maps to core portable/adapter APIs
routed_node   → JavaScript/edge hosts; maps to core portable/adapter APIs
routed_*      → framework features; not host bind/listen
server_*      → no routed imports in lib/
```

See also: [package-boundary-contract.md](./package-boundary-contract.md).

## Testing

- Core portable path: pure-Dart fakes (no sockets, no Node).
- Host packages: adapter unit tests on the VM; full bind tests only where the
  host can run (VM for IO; JS compile for real Node listen).
