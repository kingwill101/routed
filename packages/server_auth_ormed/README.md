# server_auth_ormed

`server_auth_ormed` provides durable core authentication and organization,
membership, invitation, role, and team persistence for `server_auth` without
requiring generated ORM models. All reads and writes use Ormed's fluent
table/query and mutation builders; applications can still opt into generated
models later.

The schema is exposed as normal Ormed migration entries, so it participates in
the application's migration ledger:

```dart
final database = await SqliteDatabase.connect(path: 'storage/app.sqlite');
final authSchema = const OrmAuthSchema(tablePrefix: 'auth');
final schema = const OrmAuthOrganizationSchema(tablePrefix: 'auth');

await database.migrate([
  ...authSchema.migrations,
  ...schema.migrations,
  ...appMigrations,
]);

final authStore = OrmAuthStore(database, schema: authSchema);
final organizations = OrmAuthOrganizationStore(
  database,
  schema: schema,
);
final auth = OrganizationPlugin(store: organizations);
```

`OrmAuthStore.open(database)` and `OrmAuthOrganizationStore.open(database)` are
conveniences when each adapter's migration is all that needs to be applied.
The `OrmDatabase` remains owned by the application's database provider and
should be closed with that provider. Transaction-capable Ormed drivers run
authentication and organization mutations atomically. Cloudflare D1 is also
supported: operations are serialized per database handle, and mutations that
can be staged up front use Ormed's native atomic-batch capability. D1 does not
provide a callback transaction boundary, so operations that require
read-dependent control flow remain ordered rather than wrapped in a callback
transaction.
