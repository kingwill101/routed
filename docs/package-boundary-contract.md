# Package Boundary Contract — Routed Ecosystem

This document defines the public API, provider IDs, and config roots for all split packages in `refactor-routed-modular-packages`.

## Workspace
- `routed` (slim): `Engine`, `EngineContext`, `Request`, `Response`, `Router` only
- `routed_*` (adapters): `routed_cache`, `routed_sessions`, `routed_storage`, `routed_validation`, `routed_http`, `routed_views`, `routed_auth`, `routed_rate_limit`, `routed_openapi`, `routed_observability`, `routed_security`, `routed_config`, `routed_io`, `routed_cli`, `routed_analyzer`
- `server_*` (runtimes): `server_cache`, `server_sessions`, `server_storage`, `server_rate_limit`, `server_auth`, `server_contracts`, `server_testing`, `server_native`

## Provider IDs (must be stable)
- `routed.cache`, `routed.sessions`, `routed.storage`, `routed.validation`, `routed.http`, `routed.views`, `routed.auth`, `routed.rate_limit`, `routed.localization`, `routed.observability`, `routed.security`
- `server.*` providers are framework-agnostic and not registered via `http.providers` manifest

## Config Roots
- `http.*`, `cache.*`, `session.*`, `storage.*`, `validation.*`, `views.*`, `auth.*`, `rate_limit.*`, `localization.*`, `observability.*`, `security.*`
- `routed` umbrella re-exports keep `import 'package:routed/routed.dart'` stable; direct `import 'package:routed_*/routed_*.dart'` and `import 'package:server_*/server_*.dart'` also supported

## Public API Surface
- `routed`: `Engine`, `EngineContext`, `Router`, `Route`, `Middleware`, `EngineConfig`, `Container`
- `routed_sessions`: `sessionMiddleware`, `Session`, `SessionStore`
- `routed_views`: `ViewEngine`, `ViewEngineManager`, `RoutedViewContext`
- `routed_auth`: `SessionAuth`, `GuardResult`, `guardMiddleware`
- `routed_observability`: `Tracing`, `Metrics`, `Health`
- `routed_security`: `IpFilter`, `TrustedProxyResolver`

## Three-Layer Rule
`routed` (umbrella) → `routed_*` (adapter, depends on `routed` + `server_*`) → `server_*` (pure Dart, no `routed`). No circular deps, no test code in `lib`, workspace-aware imports only.

## Verification
- `dart analyze --fatal-infos` 0
- `dart test --coverage` per package with real `Engine` (`TestClient`/`RoutedRequestHandler`, `TransportMode.ephemeralServer`)
- `coverage/lcov.info` generated via `coverage:format_coverage`
