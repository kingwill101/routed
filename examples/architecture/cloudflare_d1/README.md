# Cloudflare D1 architecture

This is the edge counterpart to [`../database_app`](../database_app). The
application code still uses `DatabaseManager`, `RoutedDatabaseProvider`,
`ctx.db()`, and the same Ormed migration API. Only the host factory changes:
`routed_node` adapts the typed `CloudflareEnvironment` and opens the `DB`
binding with `openCloudflareD1`.

The Dart Worker does not import `dart:io`, `package:web`, or JavaScript
interop. `worker_wrapper.mjs` is only the Fetch module boundary.

Create a D1 database, copy its name and ID into `wrangler.jsonc`, then build
and deploy:

```bash
npx wrangler d1 create routed-architecture-d1
dart compile js bin/worker.dart -o build/worker.dart.js -O2
npx wrangler deploy --config wrangler.jsonc

curl "$WORKER_URL/health"
curl "$WORKER_URL/api/notes"
curl -X POST "$WORKER_URL/api/notes" \
  -H 'content-type: application/json' \
  -d '{"title":"D1","body":"migrated during Worker boot"}'
```

For a production multi-instance deployment, run migrations as a release step
instead of enabling `migrateOnBoot`; the example keeps it enabled to make the
single-owner demo self-contained.

## Durable organization auth

`server_auth_ormed` can also use this D1 connection. It keeps the same
codegen-optional Ormed query builders and migrations used by the SQLite
example. D1's driver does not expose a callback transaction boundary, so the
adapter orders operations per database handle and uses Ormed native atomic
batches for mutations that can be staged up front. Read-dependent workflows
remain ordered rather than wrapped in a callback transaction.

For workflows that require a real transaction boundary, use a transactional
Ormed driver such as SQLite or Postgres. The D1 transport's explicit `batch`
API remains available for application code that needs to submit prepared D1
statements as one backend batch.
