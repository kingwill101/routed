# routed_auth_sqlite

Durable SQLite persistence for `package:server_auth` applications running on
Dart IO. The package exposes the same typed stores and transactional plugin
capabilities as the Cloudflare D1 adapter, backed by a local SQLite database
file or an in-memory database for isolated tests.

```dart
import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';
import 'package:server_auth/server_auth.dart';

final authStore = await SqliteAuthStore.openPath('var/auth.sqlite');

final options = AuthOptions<MyRequestContext>(
  store: authStore,
  providers: [CredentialsProvider()],
);

// Close the store during application shutdown.
authStore.close();
```

`SqliteAuthStore.openPath` applies idempotent, append-only migrations before
returning the store. Use `SqliteAuthStore.openInMemory` for tests and local
development. Production applications should use a durable file and configure
backups, file permissions, encryption, and process ownership according to
their deployment environment.

The adapter reuses the framework-neutral `AuthStore` contracts and the same
bounded digest-only API-key, WebAuthn, phone, anonymous, OAuth, and SCIM
storage semantics as the D1 SQL adapter. Run
`AuthStoreConformanceSuite` against any wrapper or fork before deploying a
custom SQLite topology.

This package is Dart IO only because `sqlite3` uses native SQLite bindings on
the host. Cloudflare Workers applications should use
`package:routed_auth_cloudflare` instead.
