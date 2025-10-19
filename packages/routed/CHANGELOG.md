## Unreleased

- Driver registries now throw descriptive `ProviderConfigException`s when the same driver ID is registered twice, and
  the CLI surfaces duplicate registrations through `provider:list --config` with actionable guidance.
- Session authentication now exposes `SessionAuth` helpers (login/logout/current), declarative guard middleware, and
  remember-me token rotation with documented configuration options and examples.
- Added Haigate authorization gates with a shared registry, per-route middleware helpers, provider integration, and
  configuration-driven abilities mirroring Laravel-style gates.
- Reorganized exports: core APIs remain under `package:routed/routed.dart`, while service providers and driver
  registries moved to `package:routed/providers.dart` and `package:routed/drivers.dart` respectively. Added focused
  barrels for bindings (`package:routed/bindings.dart`), middleware (`package:routed/middleware.dart`), renderers
  (`package:routed/renderers.dart`), and validation (`package:routed/validation.dart`).
- Added a first-class signal hub (`SignalHub`) that wraps routing lifecycle events (`started`, `finished`,
  `routeMatched`, `routingError`, `afterRouting`) with `connect`/`disconnect` semantics and re-publishes handler errors
  as `UnhandledSignalError` events for observability. Accessible via `AppZone.signals` and `container.make<SignalHub>()`.
- Signals now support Django-style receiver parity: `connect` returns disposable subscriptions, accepts optional
  `key`/`sender` arguments to deduplicate handlers and scope dispatch, and `UnhandledSignalError` exposes the failing
  handler's key and sender metadata.
- JWT verification and OAuth2 introspection support configurable `clockSkew` tolerances via both code and manifest
  configuration, allowing short-lived clock drift without sacrificing validation rigor.
- HTTP and HTTPS servers emit structured startup and fatal-error logs through `LoggingContext` while keeping the
  existing console output for local development.
- WebSocket routes resolve `MiddlewareRef` entries and propagate route metadata to the logging context so middleware and
  telemetry behave the same across HTTP and WebSocket endpoints.

- Unified driver registration across storage, cache, and session providers so built-in drivers register through the same
  public APIs that applications use.
- Added a storage driver registry and disk builders, enabling custom storage drivers without editing the service
  provider.
- Driver registries now accept documentation callbacks so storage/cache/session drivers can advertise their custom
  configuration keys in provider docs.
- `routed provider:driver` scaffolds starter files for storage and cache drivers, including documentation hooks that
  surface in `provider:list --config`.
- Added `logging.include_stack_traces` to control whether unhandled errors log stack traces; defaults to `false` for
  quieter production logs while keeping browser responses unchanged.
- `ctx.sse` now disables output buffering, primes the response with a `:ok` comment, flushes every frame immediately,
  and watches the shutdown controller so draining servers close SSE connections promptly.
- The HTTP accept loop processes each request concurrently, so long-lived SSE streams no longer block unrelated
  requests.
- `Response.flush()` now flushes the very first bytes even before streaming begins—SSE clients advance to the OPEN state
  instantly.
- Added `EngineContext.upgrade`, a safe alternative to socket hijacking for bespoke protocols that need direct access to
  the underlying `Socket`.
- Replaced SSE integration tests with lightweight context tests that cover event encoding, heartbeats, and error paths.
- Documented Server-Sent Events usage and added a runnable counter example, linking both into the docs navigation.

## 0.1.0

- Introduced a contextual logging API (`ctx.logger`/`LoggingContext`) and exposed configuration hooks via
  `RoutedLogger`.
- Added configurable error handling hooks (`beforeError`, `onError`, `afterError`) plus default observers for request
  failures.
- Unified middleware and handler signatures to return `Response`, ensuring predictable flow control across the pipeline.
- Refreshed binding and validation utilities with overridable rule factories and per-field message overrides.
- Tightened engine lifecycle management with request-scoped containers, request tracking, and safer size limiting.
- Updated dependencies (`contextual`, `liquify`, `decimal`, `lints`, `server_testing`), removed the unused TOML
  renderer, and bumped the SDK minimum to 3.9.0.

## 0.0.1-alpha

- Initial version.
