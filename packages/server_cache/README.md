# server_cache

Framework-agnostic cache runtime for array, file, Redis, and null-backed stores.

Depends on `server_contracts` interim (to be colocated later). Provides `CacheStore`, `ArrayStore`, `FileStore`, `RedisStore`, `NullStore`, `Repository`, `TaggedCache` etc.

Future: dissolve `server_contracts` into this package (colocated `CacheStore` contract).

## Using with Routed

`server_cache` is framework-agnostic and does not initialize a Routed provider.
For `EngineContext` helpers, depend on `routed_cache` and add
`RoutedCacheProvider` to a slim engine, or import `package:routed/routed.dart`
and use its registered cache provider.
