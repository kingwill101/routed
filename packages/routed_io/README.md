# routed_io

`dart:io` host transport for Routed.

Kept separate from **`routed_core`** so the engine can target non-`dart:io` hosts
(e.g. **Cloudflare Workers**) with a different adapter package implementing the
same core interfaces.

## Architecture

```
routed_core:  RequestAdapter / ResponseAdapter / HttpConnection / ServerTransport
     ↑
routed_io:    IoRequestAdapter, IoResponseAdapter, IoHttpConnection, IoServerTransport
     ↑
future:       WorkersRequestAdapter, … (same interfaces)
```

`IoHttpConnection` holds both `dart:io` `HttpRequest` and `HttpResponse`, and
exposes portable adapters for `Engine.handleConnection`.

## Install

```yaml
dependencies:
  routed_core: ^0.3.3
  routed_io: ^0.1.0
```

## Usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_io/routed_io.dart';

Future<void> main() async {
  final engine = Engine(providers: Engine.defaultProviders);
  engine.get('/', (ctx) => ctx.string('ok'));
  final handle = await serveIo(engine, host: '127.0.0.1', port: 8080);
  // ...
  await handle.close();
}
```

Or use the transport directly:

```dart
final transport = IoServerTransport(echo: true);
final handle = await transport.serve(
  engine,
  const ServerOptions(host: '127.0.0.1', port: 8080),
);
```

Do **not** depend on `routed_io` in Workers builds; implement the same adapter
interfaces against the Workers request/response types instead.
