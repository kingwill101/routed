# server_native

`server_native` provides a Rust-backed HTTP server runtime for Dart with a
`dart:io`-like programming model.

## Install

```yaml
dependencies:
  server_native: ^0.1.0
```

## Quick Start (`HttpServer` Style)

```dart
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  final server = await NativeHttpServer.bind('127.0.0.1', 8080, http3: false);

  await for (final request in server) {
    if (request.uri.path == '/health') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}');
      await request.response.close();
      continue;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.text
      ..write('Not Found');
    await request.response.close();
  }
}
```

## Address Semantics

`NativeHttpServer.bind()` supports `HttpServer`-style address values:

- `'127.0.0.1'`, `'::1'`, or any explicit host/IP
- `'localhost'` (loopback convenience)
- `'any'` (bind all interfaces)

You can also use:

- `NativeHttpServer.loopback(...)`
- `NativeHttpServer.bindSecure(...)`
- `NativeHttpServer.loopbackSecure(...)`

## TLS / HTTPS (Optional HTTP/3)

```dart
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  final server = await NativeHttpServer.bindSecure(
    '127.0.0.1',
    8443,
    certificatePath: 'cert.pem',
    keyPath: 'key.pem',
    http3: true,
  );

  await for (final request in server) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('secure ok');
    await request.response.close();
  }
}
```

## Callback API (`HttpRequest`)

If you prefer a callback instead of a server stream:

```dart
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  await serveFfiHttp((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('hello');
    await request.response.close();
  }, host: '127.0.0.1', port: 8080, http3: false);
}
```

## Direct Handler API (`FfiDirectRequest`)

This mode gives direct method/path/header/body access without `HttpRequest`.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  await serveFfiDirect((request) async {
    if (request.method == 'GET' && request.path == '/health') {
      return FfiDirectResponse.bytes(
        headers: const [
          MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
        ],
        bodyBytes: Uint8List.fromList(utf8.encode('{"ok":true}')),
      );
    }

    final body = await utf8.decoder.bind(request.body).join();
    return FfiDirectResponse.bytes(
      status: HttpStatus.ok,
      headers: const [
        MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
      ],
      bodyBytes: Uint8List.fromList(utf8.encode('echo: $body')),
    );
  }, host: '127.0.0.1', port: 8080, http3: false);
}
```

For lowest overhead callback routing, enable native callback mode:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  await serveFfiDirect((request) async {
    return FfiDirectResponse.bytes(
      status: HttpStatus.ok,
      headers: const [
        MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
      ],
      bodyBytes: Uint8List.fromList('ok'.codeUnits),
    );
  }, host: '127.0.0.1', port: 8080, nativeDirect: true);
}
```

## Graceful Shutdown

All boot helpers accept `shutdownSignal`.

```dart
import 'dart:async';
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  final shutdown = Completer<void>();
  final serveFuture = serveFfiHttp((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('bye');
    await request.response.close();
  }, host: '127.0.0.1', port: 8080, shutdownSignal: shutdown.future);

  // Call this from your signal handler / lifecycle hook.
  shutdown.complete();
  await serveFuture;
}
```

## DevTools Profiling Example

Use the included profiling target:

```bash
dart --observe example/devtools_profile_server.dart --mode=direct --port=8080
```

Modes:

- `--mode=direct` for direct handler path
- `--mode=http` for `HttpRequest` path

## Native Bindings

If you changed Rust FFI symbols/structs, regenerate bindings:

```bash
dart run tool/generate_ffi.dart
```

## Prebuilt Native Artifacts

Cross-platform artifacts are built by:

- `.github/workflows/server_native_prebuilt.yml`

Artifact naming:

- `server_native-<platform>.tar.gz`

Current platform labels:

- `linux-x64`, `linux-arm64`
- `macos-arm64`, `macos-x64`
- `windows-x64`, `windows-arm64`
- `android-arm64`, `android-armv7`, `android-x64`
- `ios-arm64`, `ios-sim-arm64`, `ios-sim-x64`

## Troubleshooting

If you see:

`File modified during build. Build must be rerun.`

Run the same command again once. This can happen on first native asset build.
