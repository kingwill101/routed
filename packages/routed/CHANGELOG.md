## 0.3.3

### Configuration
- `ConfigLoaderOptions` gains a `resolveEnvTemplates` flag. When `false`,
  `{{ env.* }}` Liquid expressions are preserved as raw placeholders through
  template rendering, enabling `config:cache` to generate Dart files with
  deferred environment resolution.
- `ConfigLoader.load()` now returns a `ConfigSnapshot` containing both the
  resolved config map and the raw YAML sources.
- New `buildEnvTemplateContext()` public function builds the Liquid template
  context from `Platform.environment` at runtime.
- `CoreServiceProvider.withCachedConfig()` named constructor accepts a
  `ConfigSnapshot` for zero-I/O startup from a pre-built config cache.

### Engine DX
- `Engine()` and `Engine.create()` accept an optional `configItems` parameter
  that auto-prepends a `CoreServiceProvider(configItems: ...)` to the providers
  list, eliminating the need to manually construct `CoreServiceProvider` for
  simple inline configuration.
- New `withConfigItems(Map<String, dynamic>)` EngineOpt function allows late
  config overrides that run after providers register but before boot.

### CLI and Scaffolding
- `config:cache` command generates a Dart file with a `resolveRoutedConfig()`
  function for zero-I/O startup. Supports `--output`, `--json-output`,
  `--pretty`, `--docs`, and `--docs-output` options.
- `config:clear` command removes cached config files.
- `config:publish` simplified -- generates config stubs directly from
  `buildConfigDefaults()` / `collectConfigDocs()` instead of resolving
  package roots. Added `--only` option for selective stub generation.
- `provider:list` now accepts an optional positional ID filter and displays
  config source information.
- `create` command supports Inertia scaffolding via `--inertia`,
  `--inertia-framework`, `--inertia-package-manager`, and `--inertia-output`
  flags. Entry key defaults to `index.html` for Vite 7 compatibility.
- Generated apps now include a CLI entrypoint with a built-in `serve` command.
- CLI command discovery can build engines without initialization via
  `createEngine(initialize: false)`.
- Provider and artisanal command registries are merged into generated CLI
  runners for `dart run <app>:cli`.

### Error Responses
- All error responses are now content-negotiated based on the `Accept` header,
  `X-Requested-With` (XHR detection), and request `Content-Type`. API clients
  receive JSON, browsers receive styled HTML error pages, and other clients
  receive plain text.
- New `ctx.errorResponse()` method on `EngineContext` produces a
  content-negotiated error response with status code, message, and optional
  custom JSON body override.
- New convenience getters: `ctx.wantsJson`, `ctx.acceptsHtml`, and
  `ctx.accepts(mimeType)` for inspecting client content preferences.
- Built-in error handler (`_handleGlobalError`) and 404 handler now use
  `errorResponse()` instead of hardcoded JSON.
- All built-in middleware error paths updated: `recoveryMiddleware`,
  `rateLimitMiddleware`, `basicAuthMiddleware`, `timeoutMiddleware`, and
  JWT `_writeUnauthorized`.
- **Breaking:** Clients that previously received JSON error bodies without
  sending an `Accept: application/json` header will now receive plain text
  instead. Add the `Accept` header to restore JSON responses.

### Auth
- Added `userInfoRequest` to `OAuthProvider` for non-standard userinfo flows.
- Introduced `CallbackProvider` for custom auth callbacks (ex: Telegram).
- Added WebAuthn provider types and configuration classes.
- Split auth manager internals into focused modules for options and token storage.
- Provider booting now defers until required dependency types are available and
  warns when dependencies remain unresolved.
- `AuthManager.updateSession()` replaces the authenticated identity in-place
  for both session and JWT strategies (reissues JWT cookie for JWT strategy).
- `SessionAuth.updateSession()` provides a static convenience API that
  delegates to the manager when wired by `AuthServiceProvider`.
- `AuthServiceProvider` registers `JwtVerifier` as a container instance and
  wires `SessionAuth.setSessionUpdater` for the `updateSession` facade.

### Container
- Added `waitFor<T>()`, `waitForType()`, and `makeWhenAvailable<T>()` with
  optional timeout for awaiting lazily-registered dependencies.

### Sessions
- `sessionMiddleware()` resolves `SessionConfig` from the request container
  at runtime when no explicit `store`/`name` is provided.
- Fixed post-response write guard to use `ctx.isClosed` instead of
  `ctx.response.isClosed`.

### Views
- Added a view extension registry so providers can register view engine
  extensions; Liquid applies registered extensions during rendering.

### Logging
- `RoutedLogger.createForChannel()` creates a logger with a channel override
  key merged into the context.
- `LoggingServiceProvider` reads channel-specific log levels from
  `logging.channels.*` config keys and respects the `LOG_CHANNEL` environment
  variable for default channel selection.

## 0.3.2

### OAuth Improvements
- Added `userInfoRequest` callback to `OAuthProvider` for providers that require
  custom userinfo fetching (e.g., POST instead of GET). Matches NextAuth's pattern
  for handling non-standard OAuth endpoints like Dropbox.

### Performance Optimizations
- Added `EngineFeatures.enableRequestContainerFastPath` for high-throughput scenarios
  that skips per-request container creation and uses a read-only root container.
- Added `EngineFeatures.enableTrieRouting` for optional trie-based route matching.
- Added path interning with LRU cache (`pathInternCacheSize` config option) to reduce
  string allocations during routing.
- Middleware chains are now cached per-route and invalidated when global middleware changes.
- Lazy initialization of error lists and other context state to reduce allocations.
- Added `EngineFeatures.enableSecureRequestIds` option (defaults to fast non-secure IDs).

### EngineContext Convenience Helpers
- Added `ctx.clientIP`, `ctx.remoteAddr`, `ctx.path`, `ctx.host`, `ctx.uri` shortcuts.
- Added `ctx.body()`, `ctx.bodyBytes`, `ctx.contentLength` for request body access.
- Added `ctx.statusCode` getter and `ctx.write()` for response manipulation.

### Engine API Changes
- `Engine.create()` now loads all built-in providers by default (`Engine.builtins`).
- Added `Engine.defaultProviders` for minimal core + routing setup.
- Explicit provider composition via `providers` parameter replaces `includeDefaultProviders`.
- `CoreServiceProvider` now accepts `configItems` for in-memory configuration.
- `CoreServiceProvider.withLoader()` factory for file-based configuration loading.

### Logging Improvements
- Request logger now outputs clean structured logs with `msg="Request completed"`
  and separate key=value pairs for method, path, status, duration_ms, request_id.
- `SingleFileLogDriver` now uses `PlainTextLogFormatter` by default to avoid
  ANSI escape codes in file output.

## 0.3.1

- Removed the `crypto` dependency and replaced secure cookie encryption with a
  pointycastle-backed AES-GCM implementation plus internal hash/HMAC helpers.
- Scaffold templates now live on disk and are embedded via build_runner, keeping
  template sources out of inline Dart strings.
- Web and fullstack scaffolds default to Tailwind; fullstack now renders Liquid
  layout + view files instead of inline HTML.
- Config loading now preserves `app.root` when `configDirectory` points at the
  project root.

## 0.3.0

## 0.2.0

- Introduced a full auth stack with `AuthManager`, built-in credentials/email/OAuth
  providers, session + JWT strategies, and first-class auth routes.
- Added auth callbacks/events for sign-in, sign-out, session, and JWT lifecycles,
  along with event hooks that align with routed observability signals.
- Added RBAC helpers and policy-based authorization with Haigate integration for
  ability checks and middleware wiring.
- Providers are now registry-driven with config-backed schemas, enabling dynamic
  auth provider configuration without hardcoding provider defaults.
- Auth sessions now support refresh windows via `sessionUpdateAge` and JWT update
  age refreshes for long-lived client sessions.
- Updated CLI scaffolding/templates to align with the new auth config defaults
  and testing helpers.
- Expanded auth docs and examples, including policy and JWT demo flows.

- Introduced a full localization stack: translation contracts, registry-driven
  locale resolvers (query, cookie, session, header, and custom IDs), global
  middleware, helpers (`trans`, `transChoice`, `currentLocale`), and manifest
  defaults so apps can ship multilingual responses out of the box.
- The configuration provider now leans on the shared `config_utils` helpers with
  deep merge/dot lookups, dynamic defaults for storage/session/cache, and doc
  snapshots that power `provider:list --config` output in `routed`.
- Refactored the logging provider to use the new config snapshots, tightening
  context propagation and keeping structured logger defaults in sync with the
  rest of the engine.
- Route lifecycle events now cover 404s and WebSocket handlers, publishing
  consistent metadata through `SignalHub` for observability hooks.
- Added Windows shutdown signal support so graceful server drains and CLI
  commands behave the same across platforms.

## 0.1.0

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
