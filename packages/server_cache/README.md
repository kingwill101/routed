# server_cache

Framework-agnostic cache runtime for array, file, Redis, and null-backed stores.

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
