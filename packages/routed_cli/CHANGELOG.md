# Changelog

## 0.4.0 - 2026-08-27

- **Breaking:** replace `--react-ssr-entry` with `--ssr-entry` for Cloudflare
  deployments.
- Cloudflare frontend deployments now copy the complete generated build,
  including browser assets and stylesheets, while continuing to use the
  `ssr.entry.mjs` path supplied to `--ssr-entry` for Fetch SSR. The generated
  wrapper and asset namespace are frontend-neutral, with SSR requests handled
  at `/__ssr`; custom SSR entry filenames are preserved. Repeated deploys
  replace the generated asset directory so removed files do not linger.

## 0.3.2 - 2026-08-26

- Add repeatable Cloudflare `--var NAME=VALUE` deployment options for
  explicitly provisioning plaintext Worker variables such as `AUTH_ORIGIN`.

## 0.3.1 - 2026-08-25

- Adopted `very_good_analysis` and completed public API Dartdoc coverage across
  the CLI, while preserving existing command and fluent-runner contracts.
- Expanded examples for typed scaffolding, provider command registration, and
  Cloudflare deployment bindings and factory modes.

## 0.3.0

- Cloudflare deploys now support environment-backed Worker factories with
  `--cloudflare-factory environment`, generating
  `defineCloudflareFetchFactoryWithEnvironmentAsync` for typed runtime
  bindings such as D1.
- Defer project-command discovery until an invocation selects a non-built-in
  command, so broken project commands cannot block global flags or built-ins.
- New projects now get a typed `lib/config.dart` bootstrap. `lib/app.dart`
  consumes that bootstrap so CLI route inspection, OpenAPI generation, and
  deployment use the same provider composition as the application runtime.
- Typed scaffolds now keep their shared config generic and compose only the
  providers selected by the template. Web starters use public typed view,
  storage, and static-mount constructors without YAML or implicit registries.
- `routed create --auth-plugin username` opts into the username-first server
  plugin with typed auth deployment wiring; unselected auth plugins stay out.
- Scaffold regression coverage now analyzes and compiles every generated
  project and executes its route-manifest entrypoint.
- API and full-stack templates now accept any `routed_testing` 0.x minor from
  `0.4.0` up to (but not including) `1.0.0`.
- Cloudflare deploys now generate Container Durable Object wrappers and
  `containers` configuration with `--container`.
- Cloudflare deploys now emit `workflows` and `secrets_store_secrets` binding
  configuration with `--workflow` and `--secrets-store`.
- Cloudflare deploys now accept repeatable `--d1 BINDING=DATABASE_NAME:DATABASE_ID`
  options and emit the corresponding D1 bindings in generated Wrangler config.
- Cloudflare deploys now accept repeatable `--r2`, `--queue`, and `--service`
  bindings and emit the corresponding R2, Queue producer, and service
  sections in generated Wrangler config.
- Cloudflare deployment can now generate Durable Object factory registration,
  Wrangler bindings, SQLite migrations, and named Worker class exports with
  `--durable-object`.
- Generated Durable Object exports now forward hibernation WebSocket message,
  close, and error callbacks.

## 0.2.2

- Updated the CLI to target the `routed` 0.4 provider facade.
- Fixed scaffold expectations and configuration output for the current
  provider catalog.

## 0.1.0

- Initial extraction of Routed CLI runtime/framework utilities.
- Added command runner, base command, project command loader, and dev server runner.
