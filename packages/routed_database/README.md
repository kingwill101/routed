# routed_database

Routed integration for [Ormed](https://pub.dev/packages/ormed). The package
provides Laravel-shaped application access without requiring `build_runner`:
register one or more already-open `OrmDatabase` handles, then use `ctx.db()`
from a handler.

```dart
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_database/routed_database.dart';

final database = await SqliteDatabase.connect(path: 'storage/app.sqlite');
final databases = DatabaseManager()..register('default', database);

final engine = await Engine.create(
  providers: [
    ...Engine.defaultProviders,
    RoutedDatabaseProvider(manager: databases),
  ],
);

engine.get('/users', (ctx) async {
  final rows = await ctx.db().queryRaw('SELECT * FROM users');
  return ctx.json({'users': rows});
});
```

Generated Ormed models remain available when an application wants them. The
provider does not impose a model registry or a host connection strategy. A
host adapter such as `routed_node` can create an `OrmDatabase` from a native
binding and register it with this package. When migrations are supplied, the
provider delegates them to Ormed's driver-aware migration runner.

The manager owns registered databases by default and closes them when the root
engine is cleaned up. Pass `closeOnDispose: false` for a handle owned by an
outer lifecycle. Host-backed applications can use `registerFactory` so the
provider opens the handle during its awaited boot hook instead of constructing
it in the request or route layer.

## Migrations

Ormed migrations are registered in application code and use the selected
driver's schema compiler and migration ledger:

```dart
final appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260829000100_create_users',
    const CreateUsersTable(),
  ),
];

final provider = RoutedDatabaseProvider(
  manager: databases,
  migrations: appMigrations,
  migrateOnBoot: true,
);
```

`RoutedDatabaseProvider` owns database initialization and runs this work from
Routed's awaited `ServiceProvider.boot` lifecycle hook. `Engine.initialize()`
does not accept requests until provider boot has completed, so a handler never
observes a half-initialized connection or an in-flight migration. Routing and
request events are notification streams; they are not a safe place to start
schema changes because listeners are not part of the engine's startup barrier.

`migrateOnBoot` is opt-in. For a normal multi-instance deployment, run the
same list once as a release/startup operation instead:

```dart
await databases.initialize();
final report = await databases.migrate(appMigrations);
print('Applied ${report.actions.length} migrations');
```

The ledger defaults to `orm_migrations` and can be changed per call or
provider. Cloudflare D1 keeps its own binding and atomicity constraints; the
manager delegates migration execution to Ormed rather than emulating
interactive transactions.
