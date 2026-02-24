# server_data example

Demonstrates framework-agnostic runtime implementations:

- cache via `DataCacheManager`
- storage via `StorageManager`
- session persistence via `MemorySessionStore`
- token bucket rate limiting via `RateLimitService`

## Run

```bash
dart run example/main.dart
```

## Expected output (shape)

```text
cache status = ok
storage path = .../storage/app/avatars/alice.png
session user_id = user_42
rate limit attempt 1 = allowed
rate limit attempt 2 = allowed
rate limit attempt 3 = blocked (retry after ...s)
```
