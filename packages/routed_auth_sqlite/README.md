# routed_auth_sqlite

Durable SQLite persistence for `package:server_auth` applications running on
Dart IO. The package exposes the same typed stores and transactional plugin
capabilities as the Cloudflare D1 adapter, backed by a local SQLite database
file or an in-memory database for isolated tests.

## Setup and lifecycle

Open the file-backed adapter during application startup. The `open*` helpers
apply the current idempotent schema migrations before returning, so the store
is ready to pass to your framework-neutral `AuthOptions<TContext>`:

```dart
import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';

Future<SqliteAuthStore> openAuthStore() {
  return SqliteAuthStore.openPath('var/auth.sqlite');
}

Future<void> runApplication() async {
  final authStore = await openAuthStore();
  try {
    // Pass `authStore` to AuthOptions<TContext>, then start the server.
    // The adapter provides the typed users, credentials, sessions, OAuth,
    // token, API-key, WebAuthn, and plugin-owned data stores.
  } finally {
    authStore.close();
  }
}

Future<void> main() => runApplication();
```

The parent directory of `var/auth.sqlite` must exist. Create it during
deployment or startup, and use a stable application-owned path. The adapter
does not own server shutdown; close the store only after the framework has
stopped accepting requests. Do not use the store after `close`.

For a complete runnable adapter-only lifecycle example:

```bash
dart run example/sqlite_auth_store.dart
```

Use `SqliteAuthStore.openInMemory` for tests and disposable local development.
Each call creates an isolated database and its data disappears at `close`.
Production applications should use a durable file and configure backups, file
permissions, encryption, and process ownership according to their deployment
environment.

The adapter reuses the framework-neutral `AuthStore` contracts and the same
bounded digest-only API-key, WebAuthn, phone, anonymous, OAuth, and SCIM
storage semantics as the D1 SQL adapter. Run
`AuthStoreConformanceSuite` against any wrapper or fork before deploying a
custom SQLite topology.

This package is Dart IO only because `sqlite3` uses native SQLite bindings on
the host. Cloudflare Workers applications should use
`package:routed_auth_cloudflare` instead.
