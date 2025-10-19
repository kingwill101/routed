# Routed configuration plan

Goal: dogfood every Routed configuration feature inside our own engine so the container, service providers, and runtime
code paths stay battle tested. Each milestone lists implementation work, how we will consume it internally, and the test
suites we must land before moving on.

Milestones (incremental):

1) Core container + events dogfooding
    - Implementation
        - Bind Config into the core container and the request-scoped container.
        - Emit `ConfigLoaded` on engine boot and `ConfigReloaded` on hot reload through the EventBus.
        - Add zone helpers (`Config.current`, `runWithConfig`) wired into request lifecycle.
    - Dogfooding
        - Update `Engine.initialize` to resolve Config through the container rather than reading raw maps.
        - Register a test service provider that listens for config events and mutates dependencies, proving the event
          bus wiring.
    - Tests
        - Add container tests that assert config bindings are reachable via `Container.make` and `Container.get`.
        - Add engine/event tests that listen for the new events and verify they fire with the expected payload.
        - Add request-scope tests that use `runWithConfig` to override values per request.

2) Unified config API
    - Implementation
        - Add precedence stacking: defaults (Dart) < `.env` < `config/` files < runtime overrides.
        - Provide helpers `config('app.name')`, `config<T>('db')`, and a `getOrThrow` variant.
        - Implement deep merge per top-level namespace (`app`, `db`, `mail`).
    - Dogfooding
        - Replace existing direct map access inside engine/routing/middleware with the new helper API.
        - Create a service provider that demonstrates merging package defaults with app overrides.
    - Tests
        - Add precedence tests that load fixtures across defaults/.env/files and assert final values.
        - Add helper API tests covering generics, `getOrThrow`, and merge layering.
        - Add regression tests ensuring core providers use helpers (e.g. inspect for direct map access).

3) File loaders
    - Implementation
        - Load `.env` with dotenv.
        - Load `config/*.yaml|*.yml|*.toml|*.json` into namespaced maps, supporting `config/{env}/*`.
        - Render config sources through Liquify using `.env` + process environment contexts before decoding.
        - Watch files in dev and trigger `ConfigReloaded`, replacing the container binding.
    - Dogfooding
        - Ship a `dev/config` fixture inside the repo and wire the example app to consume it.
        - Run the watcher in tests/examples to ensure reload flows operate in-process.
    - Tests
        - Add loader tests using sandboxed temp directories to validate format parsing and env layering.
        - Add watcher tests that touch files and expect `ConfigReloaded` plus updated values.
        - Add integration tests that boot an engine with fixtures to ensure reload propagates to request handlers.

4) Package defaults and ServiceProviders
    - Implementation
        - Allow packages to export `defaultConfig` (Map<String, dynamic>) plus a `ServiceProvider`.
        - Extend `Routed.configure((cfg, ioc) { ... })` to merge defaults and register dependencies.
        - Support optional validation using schema objects or typed classes with fail-fast errors (e.g.,
          provider-specific config guards).
        - Introduce provider-level validation that throws `ProviderConfigException` for malformed
          security/uploads/cors/cache/view/storage/static inputs and ensure custom providers can hook into the same
          mechanism.
        - Ensure the global `ProviderRegistry` ships entries for every built-in provider referenced by default
          manifests.
        - Surface structured logging overrides (`extra_fields`, `request_headers`) and static asset custom file systems
          through provider config.
    - Dogfooding
        - Convert existing internal packages (cache, session, view) to publish defaults + providers.
        - Consume those providers inside the main engine bootstrap instead of manual binding logic.
        - Register built-in providers inside the registry and migrate examples (e.g., config demo mail provider) to
          publish defaults via `ProvidesDefaultConfig`.
    - Tests
        - Add provider lifecycle tests that assert register/boot/cleanup order and error bubbles.
        - Add validation tests verifying schema failures throw descriptive errors.
        - Add regression suites that assert provider validation throws for malformed manifests (security trusted
          proxies, uploads limits, cors lists, cache stores, view disk overrides, custom provider defaults).
        - Add integration tests where two packages ship defaults and we ensure merge precedence works.

5) DX/CLI
    - Implementation
        - `routed config:publish <package>` copies package stubs into `config/`.
        - `routed config:cache` generates a merged Dart file for fast boot and registers it as a service.
        - `routed config:clear` removes cached artifacts.
        - `routed provider:list`, `provider:enable`, `provider:disable` expose manifest state (with `--config` surfacing
          defaults/validation hints).
    - Dogfooding
        - Hook CLI into example app CI to publish package config stubs and run from cache.
        - Use cached config inside integration tests to ensure boot without IO.
        - Validate that `provider:list --config` surfaces defaults for every built-in provider and custom providers (
          config demo).
    - Tests
        - Add CLI command tests using temp directories to assert files created/removed.
        - Add cache regression tests verifying engine loads from cached artifact when present.
        - Add provider CLI tests that assert manifest warnings for unknown providers and verify default config output.
        - Add smoke tests running example app with cached config in headless mode.

6) Codegen (optional)
    - Implementation
        - Build a `build_runner` builder generating strongly typed config classes with IDE hints.
        - Generate `AppConfig`, `DbConfig`, etc., with defaults and environment mapping.
    - Dogfooding
        - Use generated classes inside the engine and providers (e.g., typed database config).
        - Add a sample module demonstrating how to extend generated config.
    - Tests
        - Add builder tests ensuring generated code matches fixtures.
        - Add integration tests ensuring the engine compiles and runs using generated config classes.

7) Request-scope overrides
    - Implementation
        - Implement `runWithConfig` for tests and per-request tweaks; child containers override global config.
        - Ensure request containers expose overrides to downstream services resolved during the request.
    - Dogfooding
        - Update middleware tests to use overrides (e.g., toggling feature flags).
        - Use overrides in example apps to simulate tenant-specific config.
    - Tests
        - Add request lifecycle tests verifying overrides isolate per request.
        - Add concurrency tests where multiple overrides run simultaneously without bleeding state.
        - Add helper tests asserting `Config.current` respects nested override scopes.

8) Docs and examples
    - Implementation
        - Expand documentation with cookbook-style guides for config publishing, caching, and overrides.
        - Update example app to use `app.yaml`, `.env`, and hot reload sequences.
        - Document event lifecycle (`ConfigLoaded`, `ConfigReloaded`) and service provider patterns.
        - Document provider registry usage, validation errors (`ProviderConfigException`), and CLI inspection flows.
    - Dogfooding
        - Ensure docs reference fully tested flows, linking to real test cases.
        - Keep example app under integration tests so docs stay accurate.
    - Tests
        - Add doctest-style snippets or run example app tests to verify documentation samples compile.
        - Add link checkers ensuring referenced test files exist.
        - Add snapshot tests covering example output where reasonable.
        - Add documentation regression tests that execute CLI examples (`provider:list --config`) and confirm validation
          error messaging matches the docs.  
