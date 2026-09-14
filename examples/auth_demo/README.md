# Auth Demo

A new [Routed](https://kingwill101.github.io/routed/) application.

## Getting started

```bash
dart pub get
dart run routed_cli dev
```

The default route responds with a friendly JSON payload. Edit
`lib/app.dart` to add additional routes, middleware, and providers.

## Auth hooks

The demo wires auth callbacks in `lib/app.dart` and listens to auth events
through the global `EventManager` to mirror the Laravel-style event system.
Edit the typed `AuthOptions` and provider instances in `lib/app.dart` to
change the session strategy, callbacks, or OAuth providers.

Auth records are stored with `server_auth_ormed` in
`storage/auth_demo.sqlite` (or `storage/auth_demo_jwt.sqlite` for the JWT
variant). Set `AUTH_DATABASE_PATH` to override the local server path. Ormed's
code-free migration runs through `RoutedDatabaseProvider` before the engine
accepts requests.
