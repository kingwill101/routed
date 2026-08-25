/// Durable SQLite persistence for `package:server_auth` on Dart IO.
///
/// Open [SqliteAuthStore] with [SqliteAuthStore.openPath] during application
/// startup, pass it to the framework-neutral auth options, and call
/// [SqliteAuthStore.close] during shutdown:
///
/// ```dart
/// final store = await SqliteAuthStore.openPath('var/auth.sqlite');
/// try {
///   // Pass `store` to your `AuthOptions<TContext>` and start the server.
/// } finally {
///   store.close();
/// }
/// ```
///
/// [SqliteAuthStore.openInMemory] provides the same typed store contract for
/// tests and short-lived local processes. The package is Dart IO only because
/// it uses native SQLite bindings.
library;

import 'package:routed_auth_sqlite/src/sqlite_auth_store.dart';

export 'src/sqlite_auth_store.dart';
