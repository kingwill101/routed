## 0.3.0

- New projects now get a typed `lib/config.dart` bootstrap. `lib/app.dart`
  consumes that bootstrap so CLI route inspection, OpenAPI generation, and
  deployment use the same provider composition as the application runtime.
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
