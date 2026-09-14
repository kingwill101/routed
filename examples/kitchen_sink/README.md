# Kitchen Sink Example

Large catch-all demo exercising most Routed features: routing, middleware,
sessions, localization, storage, and typed provider composition. Ideal for
manual QA or workshops.

```bash
dart pub get
dart run bin/server.dart
```

Ships only inside the repo—feel free to fork and customize.

Recipes are stored in `storage/kitchen_sink.sqlite` through the
`routed_database` provider and an Ormed migration. Set `DATABASE_PATH` in your
launcher or pass `databasePath` to `buildApp` to use another SQLite file.

Recipe response caching uses the file-backed cache store at
`storage/kitchen_sink-cache`; pass `cachePath` to `buildApp` to override it.
