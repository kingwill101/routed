# server_cache

Framework-agnostic cache runtime extracted from `server_data/src/cache` per refactor.md PR F.

Depends on `server_contracts` interim (to be colocated later). Provides `CacheStore`, `ArrayStore`, `FileStore`, `RedisStore`, `NullStore`, `Repository`, `TaggedCache` etc.

Future: dissolve `server_contracts` into this package (colocated `CacheStore` contract).
