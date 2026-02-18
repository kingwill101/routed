# routed_ffi Feature Status

Last updated: February 18, 2026

## Completed Features

- Rust native transport package scaffolded in `packages/routed_ffi`.
- Dart and Rust FFI bindings wired with `ffigen` and generated `lib/src/ffi.g.dart`.
- `cbindgen` integrated in `native/build.rs` to generate C headers for Dart-side binding generation.
- Native build hooks now avoid rewriting `native/bindings.h` by default; header refresh is explicit through `tool/generate_ffi.dart` (`ROUTED_FFI_GENERATE_BINDINGS=1`) to reduce build invalidation churn.
- Rust proxy server start/stop hooks exposed over FFI:
  - `routed_ffi_transport_version`
  - `routed_ffi_start_proxy_server`
  - `routed_ffi_stop_proxy_server`
- `serveFfi` entrypoint implemented as alternative server boot path.
- `serveFfiHttp` and `serveSecureFfiHttp` entrypoints implemented for `HttpRequest`-style bridge handlers without Routed engine coupling.
- `serveFfiDirect` and `serveSecureFfiDirect` entrypoints implemented for direct Dart handlers over FFI bridge without Routed engine request pipeline.
- FFI boot APIs now expose HttpServer-like bind options (`host/address` as `String|InternetAddress`, `backlog`, `v6Only`, `shared`, and `requestClientCertificate` in TLS mode).
- Native TLS now supports `requestClientCertificate` by requesting optional client certificates and validating them against native trust roots.
- Native TLS now supports `certificatePassword` for encrypted PKCS#8 private key files.
- Native transport wired for HTTP/1 and HTTP/2 handling.
- Native TLS transport wired for `serveSecureFfi` with cert/key PEM input and ALPN (`h2`, `http/1.1`).
- Native TLS transport now supports HTTP/3/QUIC listener in secure mode when `http3` is enabled.
- Native TLS/QUIC startup now installs a rustls crypto provider before HTTP/3 initialization.
- Dedicated HTTP/3 integration test added (`serveSecureFfi serves HTTP/3 requests when enabled`) using `curl --http3-only`.
- Dedicated HTTP/3 CI workflow added (`.github/workflows/routed_ffi_http3_integration.yml`).
- Native HTTP/3 endpoint smoke tests added in `native/tests/h3_endpoint_smoke.rs`.
- Dart bridge runtime implemented to adapt routed `Engine.handleRequest` from bridge frames.
- Bridge runtime split into generic `BridgeHttpRuntime` (bridge subsystem) and `RoutedBridgeRuntime` adapter (routed subsystem) to isolate Routed-specific wiring.
- Bridge transport switched from JSON/base64 to binary framed protocol (length-prefixed payloads).
- Request/response headers and body bytes bridged as raw bytes (no base64 encoding).
- Chunked bridge framing implemented (request start/chunk/end and response start/chunk/end).
- Legacy single-frame bridge payload compatibility retained for gradual migration.
- Dart bridge runtime now streams request body chunks into `HttpRequest` and streams response body chunks out over bridge callbacks.
- Rust proxy now streams inbound HTTP body chunks into bridge request frames and streams bridge response chunks back to clients.
- Bridge socket transport latency regression addressed with persistent socket reuse tuning:
  - Bridge sockets now set `TCP_NODELAY` on Rust/Dart endpoints.
  - Bridge write path flushes at response boundaries/chunk points instead of every frame.
- Non-streaming bridge fast path now uses legacy single-frame request/response framing to reduce frame count and per-request bridge overhead.
- Bridge decode/runtime allocation pressure reduced:
  - Rust bridge idle pool moved to lightweight sync mutex for hot acquire/release path.
  - Dart frame decoder avoids redundant `Uint8List` copies when slicing payload fields.
  - Dart non-streaming response body buffer now uses `BytesBuilder(copy: false)`.
- Dart bridge request dispatch no longer relies on exception fallback for non-streaming frame detection.
- Bridge socket frame reader now uses a contiguous-chunk fast path to avoid extra payload copying when possible.
- Rust bridge response decode now maps body/chunk payloads to `Bytes` without extra copy allocations.
- Rust and Dart chunk-frame write paths now emit frame metadata + chunk bytes directly (no temporary encoded chunk payload buffers).
- Dart bridge socket frame length headers now use typed-data (`Uint32List` + `ByteData`) instead of manual bit shifts in hot-path encode/decode.
- Bridge protocol now supports tokenized header-name frame variants (`11`/`12`/`13`/`14`) under protocol v1 with legacy frame-type fallback.
- Plain HTTP accept path now sets `TCP_NODELAY` on native frontend client sockets to reduce small-request latency.
- Bridge call path now retries empty-body requests once with a fresh bridge socket when a reused socket is stale.
- Bridge backend transport now supports Unix domain sockets (auto-selected by Dart boot on Linux/macOS with TCP fallback).
- Bridge pool now includes a hot idle-socket slot before shared idle queue reuse to reduce lock/queue overhead.
- Bridge pool locking now uses `parking_lot::Mutex` on Rust side for lower-overhead acquire/release in hot paths.
- Rust bridge frame writes now use vectored writes (`write_vectored`) for frame header+payload/chunk emission.
- WebSocket upgrades are forwarded over the native bridge:
  - Rust no longer rejects websocket upgrade requests on the frontend.
  - Bridge response detach state is propagated so Dart `HttpResponse.detachSocket` can hand off upgraded sockets.
  - Upgraded socket bytes are tunneled bidirectionally over dedicated bridge tunnel frames.
  - Routed `engine.ws(...)` and plain `serveFfiHttp` websocket upgrade flows are covered by tests.
- Benchmark regression gate workflow added (`.github/workflows/routed_ffi_benchmark_gate.yml`).
- Benchmark harness now includes a native-direct mode (`routed_ffi_native_direct`) to isolate Rust front-server cost from bridge+routed overhead.
- Benchmark harness now includes a direct-handler mode (`routed_ffi_direct`) to isolate Rust front-server + bridge overhead without Routed engine execution.
- Bridge protocol specification documented in `BRIDGE_PROTOCOL.md`.
- Bridge protocol tests added/updated:
  - frame encode/decode behavior
  - runtime behavior validation
  - native proxy failure-path validation
- Baseline transport benchmark harness added (`tool/benchmark_transport.dart`) for `routed_io` vs `routed_ffi`.
- End-to-end routed_ffi tests passing.

## Outstanding Work

- Native asset build/test ergonomics need cleanup so `.dart_tool` native library refresh is always automatic.

## Suggested Next Milestones

1. Improve native asset rebuild ergonomics for local test loops and CI caching.
