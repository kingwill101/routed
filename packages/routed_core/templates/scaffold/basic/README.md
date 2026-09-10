# {{{routed:humanName}}}

A new [Routed](https://kingwill101.github.io/routed/) application.

## Getting started

```bash
dart pub get
dart run routed_cli dev
```

The default route responds with a friendly JSON payload. Edit
`lib/app.dart` to add additional routes, middleware, and providers.

Database support is included by default. The generated `lib/database.dart`
configures a file-backed SQLite database and a codegen-free Ormed migration;
`GET /db/health` verifies the provider and migration ledger.
