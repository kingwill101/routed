# Changelog

All notable changes to `server_native` will be documented in this file.

## Unreleased

- Fixed native callback websocket tunnel stability by switching direct frame polling to a non-blocking fair scheduling loop.
- Added and expanded framework compatibility tooling (`tool/framework_compat.dart`) and deterministic patch sets for `shelf`, `relic`, and `serinus`.
- Added CI workflow for framework compatibility coverage (`.github/workflows/server_native_framework_compat.yml`).
- Added `relic` A/B parity regression coverage for transfer-encoding handling, websocket ping interval behavior, graceful close, malformed host/url handling, and `connectionsInfo`.
- Added native transfer-encoding regression tests to lock behavior across lenient `GET`/`HEAD` and chunked edge-cases.
- Improved `HttpRequest` URI reconstruction and malformed-target handling parity with `dart:io`.
- Improved bridge-mode `HttpRequest`/`HttpResponse` compatibility across default headers, streaming start timing, and detach/hijack flows.
- Stabilized native callback detach/hijack handling and direct stream lifecycle cleanup under shutdown and tunnel-close races.
- Updated compatibility harness to target upstream `serinus` `main` branch and refreshed the `serinus` compat patch accordingly.

## 0.1.2

- Split large Dart runtime files into focused modules for server boot, proxy runtime, direct path, and bridge codec/request/response layers.
- Added extensive Dart and Rust internal documentation across hot-path runtime code and protocol helpers.
- Fixed `NativeMultiServer.bind` to consistently forward the `http2` flag.
- Fixed `NativeHttpServer.connectionsInfo()` tracking in native callback mode by wiring request/socket lifecycle counters on the direct callback path.
- Added callback-free direct frame polling mode for native direct transport to avoid Rust->Dart callback teardown races.
- Fixed `NativeHttpServer.close(force: true)` shutdown hangs by cancelling active Rust connection tasks during shutdown.
- Added explicit regression tests for `NativeHttpServer.close(force: true)` in both bridge and native-callback modes.
- Reduced runtime log noise by silencing expected shutdown cancellation/tunnel teardown messages by default.
- Added `server_native.verbose_logs` toggle for opt-in verbose runtime diagnostics (including non-TLS HTTP/3 downgrade notices).
- Split native binary publishing to dedicated prebuilt release tags (`server-native-prebuilt-v*`) independent from Dart package tags.
- Updated `server_native:setup` to resolve latest prebuilt-specific release tags instead of generic repository latest release.
- Added generated prebuilt release metadata (`lib/src/generated/prebuilt_release.g.dart`) sourced from `pubspec.yaml` version.
- Updated hooks/setup to use versioned prebuilt paths (`.dart_tool/server_native/prebuilt/<tag>/<platform>/`) with legacy path fallback.
- Updated prebuilt CI workflow to auto-derive release tags from package version when no tag input is provided.
- Removed `save_to_repo` prebuilt commit path from CI to avoid drift from release source-of-truth.
- Updated hook prebuilt lookup priority to prefer downloaded versioned prebuilts over packaged fallback binaries.
- Switched setup/hook cache path from `.prebuilt/...` to `.dart_tool/server_native/prebuilt/...`.
- Removed checked-in native prebuilt binaries from the repository; GitHub binary releases are now the source-of-truth.
- Added hook-level prebuilt auto-download from versioned GitHub release assets when no local prebuilt is found.
- Regenerated `native/bindings.h` and `lib/src/ffi.g.dart` to keep generated FFI artifacts in sync with native source updates.

## 0.1.1

- Reduced packaged prebuilt binary sizes for pub.dev publish limits.
- Updated prebuilt CI flow to strip artifacts and skip `ios-sim-x64` in repo prebuilts.

## 0.1.0

- Initial release of `server_native`.
- Added `NativeHttpServer` with `HttpServer`-style bind/loopback APIs.
- Added multi-bind helpers: `NativeMultiServer` and `NativeServerBind`.
- Added native callback and direct-request server modes.
- Added framework and transport benchmark harnesses and documentation.
