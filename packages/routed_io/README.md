# routed_io

`dart:io` host transport for Routed.

Kept separate from **`routed_core`** so non-`dart:io` hosts (Node, Workers)
use their own packages against the same core contracts.

See [portable-host-architecture.md](../../docs/portable-host-architecture.md).

## Paths

| Path | API |
|------|-----|
| **Native serve (default)** | `serveIo` / `IoServerTransport` → `handleConnection` (WS, streaming) |
| **Value edge** | `dispatchIoExchange` / `portableRequestFromIo` → `handlePortable` |
| **Adapters** | `IoRequestAdapter`, `IoResponseAdapter`, `IoHttpConnection` |

Declared capabilities: `HostCapabilities.ioProcess`.

## Install

```yaml
dependencies:
  routed_core: ^0.5.0
  routed_io: ^0.1.0
```

## Usage (default serve)

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_io/routed_io.dart';

Future<void> main() async {
  final engine = await Engine.create(providers: Engine.defaultProviders);
  engine.get('/', (ctx) => ctx.string('ok'));
  final handle = await serveIo(engine, host: '127.0.0.1', port: 8080);
  // ...
  await handle.close();
}
```

## Usage (portable value edge)

```dart
// Per-request (e.g. custom server loop):
await dispatchIoExchange(engine, httpRequest);

// Or force serve through handlePortable (buffers response):
await serveIo(engine, portableEdge: true);
```

## Architecture

```
routed_core:  PortableRequest / RequestAdapter / Engine.handlePortable|Connection
     ↑
routed_io:    dart:io HttpServer  (this package)
routed_node:  Node.js http
(future):     Workers fetch
```

Do **not** depend on `routed_io` in Workers/Node builds.
