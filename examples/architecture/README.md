# Routed reference architectures

These small applications are intentionally separate projects. Each one shows
one composition boundary without hiding the important wiring in generated
code:

- [`database_app`](database_app) — a normal long-lived Routed process using
  `routed_database`, SQLite, and code-free Ormed migrations.
- [`tenant_app`](tenant_app) — the same local process with sessions,
  principals, organization membership, tenant-scoped queries, and Haigate
  authorization.
- [`cloudflare_d1`](cloudflare_d1) — a Fetch Worker using the exact same
  `routed_database` provider with a Cloudflare D1 binding instead of SQLite.

The examples share the same architectural rule: the database provider owns
connection initialization and migrations, while request handlers resolve the
current principal/tenant and include the tenant key in every query. The
database package does not invent a global tenant; the application chooses its
tenant boundary explicitly.

Run an example from its directory:

```bash
dart pub get
dart run bin/server.dart
```

The Cloudflare example documents its Wrangler commands separately.
