# routed_io

`dart:io` host transport for Routed.

This package is intentionally separate from **`routed_core`** so the engine can
target non-`dart:io` hosts later (e.g. **Cloudflare Workers** / fetch-style
runtimes), the same way Node servers keep core framework logic off raw
`http.createServer` until a platform adapter is plugged in.

| Package | Responsibility |
|---------|----------------|
| `routed_core` | Routing, middleware, context, DI (host-agnostic pipeline) |
| **`routed_io`** | Bind/listen via `dart:io` (`HttpServer`, TLS file paths, …) |
| `server_native` | Optional native/Rust transport |
| (future) workers adapter | Cloudflare / edge fetch entrypoints |

## Install

```yaml
dependencies:
  routed_core: ^0.3.3   # or package:routed for batteries
  routed_io: ^0.1.0
```

## Usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_io/routed_io.dart';

Future<void> main() async {
  final engine = await Engine.create();
  await serveIo(engine, host: '127.0.0.1', port: 8080);
}
```

Use `serveSecureIo(...)` for TLS boot with certificate/key paths.

Do **not** pull `routed_io` into Workers or other edge builds; depend on core
(and a workers transport) only.
