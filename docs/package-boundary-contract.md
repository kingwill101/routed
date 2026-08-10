# Package Boundary Contract — Routed Ecosystem

## Roles

| Package | Role |
|---------|------|
| **`routed_core`** | Slim foundation: `Engine`, `EngineContext`, `Request`, `Response`, `Router`, config, DI. Transport-agnostic request pipeline. |
| **`routed`** | Batteries-included default for apps: re-exports core + official adapters/runtimes and registers providers |
| **`routed_io`** | **`dart:io` HTTP(S) bind/serve** (and related host I/O). Kept separate so core can target non-`dart:io` hosts (Cloudflare Workers, etc.). |
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
 ├── server_native      native/Rust transport (optional)
 └── (future) workers   Cloudflare Workers / fetch-handler style host
```

**Rule:** anything that binds sockets, TLS files, `HttpServer`, process env files, or other host I/O belongs in a **transport package** (`routed_io`, `server_native`, future workers package)—not in application-facing feature adapters and not as the only way to run `Engine`.

Today `routed_core` still has residual `dart:io` usage (`HttpRequest`/`HttpServer` paths, security helpers). Workers readiness means shrinking that surface behind adapters until core can compile without host I/O.

## Dependency rules

```
app (VM server)     → package:routed + package:routed_io  (or server_native)
app (Workers later) → package:routed_core (+ workers transport) — no routed_io

adapter package → routed_core + server_*   (never depend on package:routed)
server_*        → no routed / routed_core
routed_io       → routed_core + dart:io
```

## Canonical imports

```dart
// Applications (full framework)
import 'package:routed/routed.dart';
import 'package:routed_io/routed_io.dart'; // VM bind/serve

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
