# {{{routed:humanName}}}

This project exposes a JSON API using [Routed](https://kingwill101.github.io/routed/).

## Useful scripts

```bash
dart pub get
```

```
# Run the API locally on port 8080
dart run routed_cli dev
```

### Example requests

```
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/users
curl http://localhost:8080/db/health
```

See `lib/app.dart` for the complete route definitions. `test/api_test.dart`
shows how to exercise the engine with `routed_testing`. Database support is
provided by `RoutedDatabaseProvider` in `lib/config.dart`; edit
`lib/database.dart` to add Ormed migrations or replace SQLite with a host
adapter such as Cloudflare D1.
