# server_cache

Framework-agnostic cache runtime for array, file, Ormed database, Redis, and
null-backed stores.

Stores are concrete objects. Reusable construction uses typed options rather
than string-keyed configuration maps:

```dart
final manager = DataCacheManager()
  ..registerStore('memory', ArrayStore())
  ..registerStoreFactory(
    'redis',
    RedisStoreFactory(),
    const RedisStoreConfiguration(host: '127.0.0.1', port: 6379),
  );

final repository = manager.store('memory');
```

## Ormed database store

`OrmCacheStore` uses Ormed's codegen-free query builder and accepts an already
opened `OrmDatabase`. It does not choose a database driver, so the same store
works with SQLite, Cloudflare D1, and other Ormed adapters. Register its
migration with the application's normal database provider before serving
requests:

```dart
final cache = OrmCacheStore(database);
await database.migrate([cache.migration]);

final manager = DataCacheManager()..registerStore('database', cache);
final repository = manager.store('database');
```

In a Routed application, pass the same `cache.migration` entry to
`RoutedDatabaseProvider` with `migrateOnBoot: true` instead of calling
`database.migrate` directly.

Cache values are JSON encoded. The store does not automatically create or
drop tables, and it does not provide distributed locks; use a lock-capable
store when a read-modify-write operation must be serialized across workers.

`FileStoreConfiguration`, `RedisStoreConfiguration`,
`ArrayStoreConfiguration`, and `NullStoreConfiguration` are the built-in
typed options. Custom adapters implement `StoreFactory<T>` for their own
configuration type.

Depends on `server_contracts` interim (to be colocated later). Provides `CacheStore`, `ArrayStore`, `FileStore`, `RedisStore`, `NullStore`, `Repository`, `TaggedCache` etc.

Future: dissolve `server_contracts` into this package (colocated `CacheStore` contract).

## Using with Routed

`server_cache` is framework-agnostic and does not initialize a Routed provider.
For `EngineContext` helpers, depend on `routed_cache` and add
`RoutedCacheProvider` to a slim engine, or import `package:routed/routed.dart`
and use its registered cache provider.
