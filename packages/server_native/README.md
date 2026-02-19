# server_native

`server_native` provides a Rust-backed HTTP server runtime for Dart with a
`dart:io`-like programming model.
For most server code, it is intended to be a drop-in replacement for
`HttpServer`: keep the same request/response handling and swap only the bind
bootstrap.

## Table Of Contents

- [Install](#install)
- [Quick Start (`HttpServer` Style)](#quick-start-httpserver-style)
- [Drop-In `HttpServer` Replacement](#drop-in-httpserver-replacement)
- [Protocol Support (HTTP/1.1, HTTP/2, HTTP/3)](#protocol-support-http11-http2-http3)
- [Address Semantics](#address-semantics)
- [Multi-Server Binding (`NativeHttpServer.loopback`)](#multi-server-binding-nativehttpserverloopback)
- [Multi-Server Binding Shortcut (`localhost` / `any`)](#multi-server-binding-shortcut-localhost--any)
- [TLS / HTTPS (Optional HTTP/3)](#tls--https-optional-http3)
- [Callback API (`HttpRequest`)](#callback-api-httprequest)
- [Direct Handler API (`NativeDirectRequest`)](#direct-handler-api-nativedirectrequest)
- [Graceful Shutdown](#graceful-shutdown)
- [DevTools Profiling Example](#devtools-profiling-example)
- [Framework Benchmarks](#framework-benchmarks)
- [Native Bindings](#native-bindings)
- [Prebuilt Native Artifacts](#prebuilt-native-artifacts)
- [Troubleshooting](#troubleshooting)

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

## Drop-In `HttpServer` Replacement

Existing `HttpRequest`/`HttpResponse` logic can remain unchanged.
Typical migration:

- before: `HttpServer.bind(...)`
- after: `NativeHttpServer.bind(...)`

```dart
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  final HttpServer server = await NativeHttpServer.bind('127.0.0.1', 8080);
  await for (final request in server) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('drop-in ok');
    await request.response.close();
  }
}
```

## Protocol Support (HTTP/1.1, HTTP/2, HTTP/3)

- HTTP/1.1: supported for plaintext and TLS servers.
- HTTP/2: controlled explicitly with `http2` (defaults to `true`).
- HTTP/3: supported only with TLS and QUIC.

Notes:

- TLS certificates do not implicitly force HTTP/2. If you want TLS + HTTP/1.1
  only, set `http2: false`.
- `http3` options default to `true`, but HTTP/3 is automatically disabled for
  insecure (non-TLS) server boots.
- If TLS cert/key are not configured, server boots run in HTTP/1.1 + optional
  HTTP/2 mode only (based on `http2`).

## Address Semantics

`NativeHttpServer.bind()` supports `HttpServer`-style address values:

- `'127.0.0.1'`, `'::1'`, or any explicit host/IP
- `'localhost'` (loopback convenience)
- `'any'` (bind all interfaces)

You can also use:

- `NativeHttpServer.loopback(...)`
- `NativeHttpServer.bindSecure(...)`
- `NativeHttpServer.loopbackSecure(...)`

## Multi-Server Binding (`NativeHttpServer.loopback`)

Bind one logical server across all loopback interfaces (`127.0.0.1` and `::1`
when available) with a single `HttpServer` stream:

```dart
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  final server = await NativeHttpServer.loopback(8080, http3: false);

  await for (final request in server) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('loopback multi-server ok');
    await request.response.close();
  }
}
```

## Multi-Server Binding Shortcut (`localhost` / `any`)

Use `bind()` with `localhost` (loopback interfaces) or `any` (all interfaces)
to get multi-interface binding through a single `HttpServer`:

```dart
import 'dart:io';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  final server = await NativeHttpServer.bind('localhost', 8080, http3: false);
  // Equivalent patterns:
  // final server = await NativeHttpServer.bind('any', 8080, http3: false);
  // final server = await NativeHttpServer.loopback(8080, http3: false);

  await for (final request in server) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('localhost multi-server ok');
    await request.response.close();
  }
}
```

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
    http2: true,
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
  await serveNativeHttp((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('hello');
    await request.response.close();
  }, host: '127.0.0.1', port: 8080, http3: false);
}
```

`nativeCallback` defaults to `true` for `NativeHttpServer` and `serveNative*`
`HttpRequest` APIs, which means direct FFI callback transport is used by
default. Set `nativeCallback: false` to force bridge socket transport.
WebSocket upgrade is supported in either mode.

## Direct Handler API (`NativeDirectRequest`)

This mode gives direct method/path/header/body access without `HttpRequest`.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/server_native.dart';

Future<void> main() async {
  await serveNativeDirect((request) async {
    if (request.method == 'GET' && request.path == '/health') {
      return NativeDirectResponse.bytes(
        headers: const [
          MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
        ],
        bodyBytes: Uint8List.fromList(utf8.encode('{"ok":true}')),
      );
    }

    final body = await utf8.decoder.bind(request.body).join();
    return NativeDirectResponse.bytes(
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
  await serveNativeDirect((request) async {
    return NativeDirectResponse.bytes(
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
  final serveFuture = serveNativeHttp((request) async {
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

## Framework Benchmarks

Framework transport benchmarks live in `benchmarks/`:

```bash
dart run benchmarks/framework_transport_benchmark.dart --framework=all
```

Latest harness snapshot (February 19, 2026; `requests=2500`, `concurrency=64`,
`warmup=300`, `iterations=25`):

Note: these values were measured on a local development machine and are
intended for relative comparison. See `benchmarks/README.md` for full test
machine specs and run context.

Mode meaning in this table:

- `nativeCallback=true`: `NativeHttpServer` uses direct FFI callback handling
  (bridge socket bypassed).
- `nativeCallback=false`: `NativeHttpServer` uses the bridge socket/frame
  transport between Rust and Dart.

| Mode | Top result | req/s | p95 |
| --- | --- | ---: | ---: |
| `nativeCallback=true` | `native_direct_rust` | 12362 | 6.34 ms |
| `nativeCallback=false` | `native_direct_rust` | 12656 | 6.17 ms |

Framework pair highlights from the same harness:

| Framework | `*_io` | `*_native` (`nativeCallback=true`) | `*_native` (`nativeCallback=false`) |
| --- | ---: | ---: | ---: |
| `dart:io` | 7703 req/s, p95 9.72 ms | 8370 req/s, p95 9.05 ms | 7565 req/s, p95 10.60 ms |
| `routed` | 5703 req/s, p95 12.51 ms | 7110 req/s, p95 10.88 ms | 6392 req/s, p95 11.93 ms |
| `relic` | 5073 req/s, p95 14.46 ms | 6823 req/s, p95 11.31 ms | 5990 req/s, p95 12.73 ms |
| `shelf` | 5181 req/s, p95 14.08 ms | 6524 req/s, p95 11.66 ms | 5843 req/s, p95 13.07 ms |

See `benchmarks/README.md` for full result tables, options, and case labels.

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
