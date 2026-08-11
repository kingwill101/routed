# Package Boundary Contract — Routed Ecosystem

## Roles

| Package | Role |
|---------|------|
| **`routed_core`** | Slim foundation: `Engine`, `EngineContext`, `Request`, `Response`, `Router`, config, DI. Transport-agnostic request pipeline. |
| **`routed`** | Batteries-included default for apps: re-exports core + official adapters/runtimes and registers providers |
| **`routed_io`** | **`dart:io` HTTP(S) bind/serve** (and related host I/O). Kept separate so core can target non-`dart:io` hosts (Cloudflare Workers, Node, etc.). |
| **`routed_node`** | **Node.js HTTP host** (`IncomingMessage` / `ServerResponse` adapters + `http.createServer` transport). Optional; same core primitives as `routed_io`. |
| **`routed_*`** | Framework adapters on `routed_core` + `server_*` |
| **`server_*`** | Portable runtimes (no framework imports in `lib/`) |
| **`server_native`** | Optional Rust/native transport (also not part of core) |

## Runtime / host transports

Apps choose a host adapter; core must not assume Node-style process I/O forever:

```
routed_core  ←  request pipeline, routing, middleware, DI
     ↑
     │  ServerTransport / RequestAdapter (abstract)
     │
 ├── routed_io          dart:io HttpServer (typical VM / server process)
 ├── routed_node        Node.js http.createServer (JS interop)
 ├── server_native      native/Rust transport (optional)
 └── (future) workers   Cloudflare Workers / fetch-handler style host
```

**Rule:** anything that binds sockets, TLS files, `HttpServer`, process env files, or other host I/O belongs in a **transport package** (`routed_io`, `routed_node`, `server_native`, future workers package)—not in application-facing feature adapters and not as the only way to run `Engine`.

Today `routed_core` still has residual `dart:io` usage (`HttpRequest`/`HttpServer` paths, security helpers). Portable hosts use `Engine.handlePortable` / `Engine.handleConnection`; core bridges via `AdapterHttpBridge` until the pipeline is fully portable.

Longer design: [portable-host-architecture.md](./portable-host-architecture.md).

## Dependency rules

```
app (VM server)     → package:routed + package:routed_io  (or server_native)
app (Node host)     → package:routed_core + package:routed_node  (no routed_io)
app (Workers later) → package:routed_core (+ workers transport) — no routed_io

adapter package → routed_core + server_*   (never depend on package:routed)
server_*        → no routed / routed_core
routed_io       → routed_core + dart:io
                  dispatchIoExchange / portableRequestFromIo (value edge)
                  serveIo native fast path by default; portableEdge optional
routed_node     → routed_core (+ JS interop for bind)
                  dispatchNodeExchange / portableRequestFromNode (value edge)
```

## Canonical imports

```dart
// Applications (full framework, VM)
import 'package:routed/routed.dart';
import 'package:routed_io/routed_io.dart'; // VM bind/serve

// Node host
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/routed_node.dart';

// Adapter authors / minimal surface
import 'package:routed_core/routed_core.dart';
import 'package:routed_core/providers.dart';
```

## Provider IDs

- Core registry defaults: `routed.core`, `routed.routing`, `routed.uploads`
- Registered when importing `package:routed`: auth, logging, views, localization, observability, cache, sessions, storage, rate_limit

## Verification

- Adapters depend only on `routed_core` (not batteries `routed`)
- `server_*` lib purity tests pass
- No circular deps
