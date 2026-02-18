# routed_ffi

`routed_ffi` provides explicit boot helpers for the Rust-backed transport
experiment in Routed.

This package boots a Rust-native front transport and forwards typed binary
request/response frames into the Routed engine through a private bridge socket.
This enables an end-to-end native transport path while parity work continues.

## Install

```yaml
dependencies:
  routed_ffi: ^0.1.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:routed_ffi/routed_ffi.dart';

Future<void> main() async {
  final engine = await Engine.create();
  await serveFfi(engine, host: '127.0.0.1', port: 8080, http3: false);
}
```

Use `serveSecureFfi(...)` for TLS boot (PEM cert + key required):

```dart
import 'package:routed/routed.dart';
import 'package:routed_ffi/routed_ffi.dart';

Future<void> main() async {
  final engine = await Engine.create();
  await serveSecureFfi(
    engine,
    address: '127.0.0.1',
    port: 8443,
    certificatePath: 'cert.pem',
    keyPath: 'key.pem',
    http3: false,
  );
}
```

Use `serveFfiDirect(...)` to keep the Rust transport + FFI bridge but bypass
Routed engine handling entirely:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed_ffi/routed_ffi.dart';

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

    if (request.method == 'POST' && request.path == '/echo') {
      final body = await utf8.decoder.bind(request.body).join();
      final payload = jsonEncode({
        'method': request.method,
        'path': request.path,
        'query': request.query,
        'body': body,
      });
      return FfiDirectResponse.bytes(
        headers: const [
          MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
        ],
        bodyBytes: Uint8List.fromList(utf8.encode(payload)),
      );
    }

    return FfiDirectResponse.bytes(
      status: HttpStatus.notFound,
      headers: const [
        MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
      ],
      bodyBytes: Uint8List.fromList(utf8.encode('Not Found')),
    );
  }, host: '127.0.0.1', port: 8080, http3: false);
}
```

Use `serveFfiHttp(...)` to use bridge transport with a plain `HttpRequest`
handler (closest to `dart:io` `HttpServer.listen(...)` style):

```dart
import 'dart:io';

import 'package:routed_ffi/routed_ffi.dart';

Future<void> main() async {
  await serveFfiHttp((request) async {
    request.response.headers.contentType = ContentType.text;
    request.response.write('hello from ffi http bridge');
    await request.response.close();
  }, host: '127.0.0.1', port: 8080, http3: false);
}
```

## Current Status

- `serveFfi(...)`: Rust native front server is active (HTTP/1 + HTTP/2).
- `serveSecureFfi(...)`: Rust native TLS front server is active (HTTP/1 + HTTP/2 + HTTP/3).
- `serveFfiHttp(...)` / `serveSecureFfiHttp(...)`: Rust native front server is active with `HttpRequest` handlers and no Routed engine coupling.
- `serveFfiDirect(...)` / `serveSecureFfiDirect(...)`: Rust native front server is active with direct Dart handlers (no Routed engine request pipeline).
- FFI boot APIs accept HttpServer-like bind options (`host/address` as `String` or `InternetAddress`, plus `backlog`, `v6Only`, and `shared`).
- `requestClientCertificate` is supported in TLS APIs; the transport requests optional client certificates and validates them against native trust roots when provided.
- `certificatePassword` is supported for encrypted PKCS#8 private key files (`BEGIN ENCRYPTED PRIVATE KEY`).
- bridge transport: binary framed protocol with chunked request/response exchange (no JSON/base64 in hot path).
- WebSocket upgrades are forwarded over the bridge (including Routed `engine.ws(...)` and plain `serveFfiHttp` handlers using `WebSocketTransformer.upgrade`).
- Dart bridge runtime streams chunked request/response bodies to/from Routed handlers.
- Rust proxy streams request/response body data through bridge frames (no full proxy-body buffering path).
- HTTP/3 is enabled only for TLS mode (`serveSecureFfi`) when `http3: true`.
- Native startup installs a rustls crypto provider for QUIC before enabling HTTP/3.
- Dedicated HTTP/3 integration coverage exists in `test/serve_ffi_test.dart` and CI workflow `.github/workflows/routed_ffi_http3_integration.yml`.

## Bridge Protocol

- Protocol spec: `BRIDGE_PROTOCOL.md`

## Binding Generation

- Rust exports C headers via `native/build.rs` using `cbindgen`.
- Dart bindings are generated with `ffigen`:

```bash
dart run tool/generate_ffi.dart
```

## Benchmark

Run the local transport benchmark (`dart_io_direct`, `routed_io`, `routed_ffi_direct`, `routed_ffi`, and native-direct `routed_ffi_native_direct`):

```bash
dart run tool/benchmark_transport.dart
```

Optional flags:

- `--requests=N`
- `--concurrency=N`
- `--warmup=N`
- `--host=ADDR`
- `--iterations=N`
- `--min-req-per-sec-ratio=R`
- `--max-p95-ratio=R`
- `--json`

CI runs a benchmark gate workflow at `.github/workflows/routed_ffi_benchmark_gate.yml`
using ratio thresholds to catch performance regressions.

`routed_ffi_native_direct` is a benchmark-only native mode that serves a static
JSON response from Rust without bridge/routed execution. It is intended for
transport-cost isolation, not application serving.

`dart_io_direct` is a benchmark-only pure `dart:io` `HttpServer` mode that serves
the same static JSON response shape without Routed engine execution.

`routed_ffi_direct` is a benchmark mode using `serveFfiDirect(...)` (Rust front
server + FFI bridge + direct Dart handler) without Routed engine execution.

### Latest Snapshot

Last run (local): 2026-02-17 21:30 -0500

Command:

```bash
dart run tool/benchmark_transport.dart \
  --requests=2500 \
  --concurrency=64 \
  --warmup=300 \
  --iterations=5 \
  --json
```

Result summary:

- `routed_io`: `4746.12 req/s`, `p50=15.19 ms`, `p95=15.19 ms`
- `routed_ffi`: `6615.23 req/s`, `p50=11.56 ms`, `p95=11.56 ms`
- `routed_ffi_native_direct`: `11560.85 req/s`, `p50=8.56 ms`, `p95=8.56 ms`
Ratios:
- `routed_ffi / routed_io`: throughput `1.394`, p95 `0.761`
- `routed_ffi_native_direct / routed_io`: throughput `2.436`, p95 `0.563`
- `routed_ffi_native_direct / routed_ffi`: throughput `1.748`, p95 `0.741`

Interpretation:
- The Rust native front path remains much faster than routed execution (`routed_ffi_native_direct`).
- Bridge transport latency regression was reduced via bridge socket `TCP_NODELAY` + fewer per-frame flushes.
- Additional bridge overhead was reduced by using legacy single-frame fast paths for non-streaming request/response handling and reducing Dart-side byte copies in frame decode.
- Serialization/deserialization overhead was further reduced by:
  - zero-copy Rust decode of Dart response body/chunk frame payloads into `Bytes`,
  - direct chunk frame writes (no temporary encoded chunk payload buffers) in both Rust and Dart bridge paths.
- Low-concurrency path was improved by enabling `TCP_NODELAY` on accepted plain HTTP sockets in the native Rust front server.
- Bridge idle socket robustness was preserved without per-request probe overhead by retrying once with a fresh socket for failed empty-body bridge calls.
- Bridge transport now auto-selects Unix domain sockets on Linux/macOS (fallback to loopback TCP), reducing local bridge overhead while preserving the same public boot API.
- Bridge pool now keeps a hot idle-socket slot before falling back to the shared idle vector, reducing lock contention in the common reuse path.
- With this run profile, `routed_ffi` now exceeds `routed_io` throughput and p95 latency.

## Troubleshooting

### Native Asset Rebuild

If you see this during benchmark/test runs:

`File modified during build. Build must be rerun.`

Run the same command again immediately. This can happen when native build hooks
refresh `.dart_tool` artifacts on first invocation.
