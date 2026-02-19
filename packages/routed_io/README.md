# routed_io

`routed_io` provides explicit boot helpers for running Routed servers on the
existing `dart:io` transport.

## Install

```yaml
dependencies:
  routed_io: ^0.1.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:routed_io/routed_io.dart';

Future<void> main() async {
  final engine = await Engine.create();
  await serveIo(engine, host: '127.0.0.1', port: 8080);
}
```

Use `serveSecureIo(...)` for TLS boot.
