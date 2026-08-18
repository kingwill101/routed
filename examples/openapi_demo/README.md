# Openapi Demo

This project exposes a JSON API using [Routed](https://kingwill101.github.io/routed/).

## Useful scripts

```bash
dart pub get

# Generate the runtime manifest and static OpenAPI outputs
dart run routed_cli openapi generate
dart run build_runner build --delete-conflicting-outputs
```

```
# Run the API locally on port 8080
dart run routed_cli dev
```

### Example requests

```
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/users
```

The demo includes nested `/catalog/v2` and `/admin/v2` route groups. Nested
prefixes may be arbitrarily deep; the runtime manifest flattens them into the
paths served by the engine. See `lib/app.dart` and `lib/metadata_routes.dart`
for fluent metadata and nested-group examples. `test/api_test.dart` verifies
that the runtime and generated OpenAPI documents match.
