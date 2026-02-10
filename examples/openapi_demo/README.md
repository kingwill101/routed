# Openapi Demo

This project exposes a JSON API using [Routed](https://routed.dev).

## Useful scripts

```bash
dart pub get
```

```
# Run the API locally on port 8080
dart run routed dev
```

### Example requests

```
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/users
```

See `lib/app.dart` for the complete route definitions. `test/api_test.dart`
shows how to exercise the engine with `routed_testing`.
