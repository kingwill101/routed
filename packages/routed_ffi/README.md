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

## DevTools Profiling Example

Use `example/devtools_profile_server.dart` as a local profiling target.

Start with VM service enabled:

```bash
dart --observe example/devtools_profile_server.dart --mode=direct --port=8080
```

Then drive traffic:

```bash
curl http://127.0.0.1:8080/health
curl "http://127.0.0.1:8080/cpu?iterations=800000&seed=7"
curl -X POST http://127.0.0.1:8080/upload --data-binary @/tmp/payload.bin
curl -X POST http://127.0.0.1:8080/echo --data-binary @/tmp/payload.bin
```

Notes:
- `/upload` streams and counts request bytes without buffering the full payload in
  user code (better for bridge/runtime profiling).
- `/echo` intentionally collects the full body in memory and includes a preview
  (useful when you want application buffering to show up in the profile).

Switch to `HttpRequest` adapter mode if needed:

```bash
dart --observe example/devtools_profile_server.dart --mode=http --port=8080
```

## Current Status

- `serveFfi(...)`: Rust native front server is active (HTTP/1 + HTTP/2).
- `serveFfi(..., nativeCallback: true)`: Routed engine over native callback request/response frames (no bridge backend socket hop for that mode).
- `serveSecureFfi(...)`: Rust native TLS front server is active (HTTP/1 + HTTP/2 + HTTP/3).
- `serveFfiHttp(...)` / `serveSecureFfiHttp(...)`: Rust native front server is active with `HttpRequest` handlers and no Routed engine coupling.
- `serveFfiDirect(...)` / `serveSecureFfiDirect(...)`: Rust native front server is active with direct Dart handlers (no Routed engine request pipeline).
- `serveFfiDirect(..., nativeDirect: true)` / `serveSecureFfiDirect(..., nativeDirect: true)` now run fully over native callback frames (no bridge backend socket hop for that mode), including chunked request/response frame flow.
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
- Normal native build hooks do not rewrite `native/bindings.h` to avoid
  first-run invalidation churn.
- Dart bindings are generated with `ffigen` using:

```bash
dart run tool/generate_ffi.dart
```

`tool/generate_ffi.dart` first runs Cargo with
`ROUTED_FFI_GENERATE_BINDINGS=1` to refresh `native/bindings.h`, then runs
`ffigen`.

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
- `--include-direct-native-callback`
- `--include-routed-native-callback`

CI runs a benchmark gate workflow at `.github/workflows/routed_ffi_benchmark_gate.yml`
using ratio thresholds to catch performance regressions.

`routed_ffi_native_direct` is a benchmark-only native mode that serves a static
JSON response from Rust without bridge/routed execution. It is intended for
transport-cost isolation, not application serving.

`dart_io_direct` is a benchmark-only pure `dart:io` `HttpServer` mode that serves
the same static JSON response shape without Routed engine execution.

`routed_ffi_direct` is a benchmark mode using `serveFfiDirect(...)` (Rust front
server + FFI bridge + direct Dart handler) without Routed engine execution.

`routed_ffi_native_callback` is a benchmark mode using
`serveFfi(..., nativeCallback: true)` (Routed engine over native callback frames)
without the bridge backend socket hop.

### Latest Snapshot

Last run (local): 2026-02-18 11:33 -0500 (terminal summary via `--pretty`)

Command:

```bash
dart run tool/benchmark_transport.dart \
  --requests=2500 \
  --concurrency=64 \
  --warmup=10 \
  --iterations=25 \
  --include-direct-native-callback \
  --pretty
```

Result summary:

- `dart_io_direct`: `6907 req/s`, `p50=10.55 ms`, `p95=10.55 ms`
- `routed_io`: `5850 req/s`, `p50=13.30 ms`, `p95=13.30 ms`
- `routed_ffi_direct`: `9689 req/s`, `p50=7.95 ms`, `p95=7.95 ms`
- `routed_ffi_direct_native_callback`: `12584 req/s`, `p50=6.34 ms`, `p95=6.34 ms`
- `routed_ffi`: `6902 req/s`, `p50=10.90 ms`, `p95=10.90 ms`
- `routed_ffi_native_direct`: `13636 req/s`, `p50=5.73 ms`, `p95=5.73 ms`
Ratios:
- `routed_ffi / routed_io`: throughput `1.180`, p95 `0.820`
- `routed_ffi_direct / dart_io_direct`: throughput `1.402`, p95 `0.753`
- `routed_ffi_direct_native_callback / routed_ffi_direct`: throughput `1.299`, p95 `0.797`
- `routed_ffi_native_direct / routed_ffi_direct_native_callback`: throughput `1.084`, p95 `0.904`

Interpretation:
- The Rust native front path remains much faster than routed execution (`routed_ffi_native_direct`).
- `routed_ffi_direct_native_callback` is now the fastest Dart-involved path by throughput and p95.
- `routed_ffi_direct_native_callback` materially narrows the gap to the Rust-only baseline.
- This snapshot uses 25 iterations and includes the direct native callback transport mode.

### Snapshot History

- `2026-02-18 16:40 +0000` (Ubuntu `ubuntu-s-1vcpu-512mb-10gb-sfo3-01`, bundled CLI, `2500/64/10/25`, `--include-direct-native-callback`):
- `dart_io_direct`: `4113 req/s`
- `routed_io`: `3336 req/s`
- `routed_ffi_direct`: `3765 req/s`
- `routed_ffi_direct_native_callback`: `4547 req/s`
- `routed_ffi`: `3079 req/s`
- `routed_ffi_native_direct`: `5892 req/s`
- `2026-02-18 06:46 -0500` (`benchmark_v1_direct_payload_lazy_25iter_2500req.json`):
- `dart_io_direct`: `7030.53 req/s`
- `routed_io`: `5697.89 req/s`
- `routed_ffi_direct`: `9618.75 req/s`
- `routed_ffi`: `7294.82 req/s`
- `routed_ffi_native_direct`: `13592.50 req/s`
- `2026-02-18 04:22 -0500` (`benchmark_v1_coalesce_writes_lenread_25iter_run2.json`):
- `dart_io_direct`: `5692.08 req/s`
- `routed_io`: `4580.04 req/s`
- `routed_ffi_direct`: `8183.04 req/s`
- `routed_ffi`: `6437.89 req/s`
- `routed_ffi_native_direct`: `10838.84 req/s`
- Note: all transports dropped together in this run, indicating host load variance rather than an isolated FFI regression.

## Troubleshooting

### Native Asset Rebuild

If you see this during benchmark/test runs:

`File modified during build. Build must be rerun.`

Run the same command again immediately. This can happen when native build hooks
refresh `.dart_tool` artifacts on first invocation.

If you changed native Rust FFI structs/functions, run:

```bash
dart run tool/generate_ffi.dart
```

before benchmark/test commands so `bindings.h` and `lib/src/ffi.g.dart` are in
sync.
