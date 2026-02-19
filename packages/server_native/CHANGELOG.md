# Changelog

All notable changes to `server_native` will be documented in this file.

## 0.1.1

- Reduced packaged prebuilt binary sizes for pub.dev publish limits.
- Updated prebuilt CI flow to strip artifacts and skip `ios-sim-x64` in repo prebuilts.

## 0.1.0

- Initial release of `server_native`.
- Added `NativeHttpServer` with `HttpServer`-style bind/loopback APIs.
- Added multi-bind helpers: `NativeMultiServer` and `NativeServerBind`.
- Added native callback and direct-request server modes.
- Added framework and transport benchmark harnesses and documentation.
