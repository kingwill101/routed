# Rate limiting example

This example demonstrates token-bucket, sliding-window, and quota policies.
Rate-limit counters are persisted through an Ormed query-builder adapter backed
by SQLite, so restarting the server does not reset the counters.

```bash
dart pub get
dart run bin/server.dart
dart run bin/client.dart
```

The server uses `storage/rate_limiting.sqlite` by default. Set
`DATABASE_PATH` to point it at another SQLite file.
