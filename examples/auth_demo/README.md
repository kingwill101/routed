# Auth Demo

A new [Routed](https://routed.dev) application.

## Getting started

```bash
dart pub get
dart run routed dev
```

The default route responds with a friendly JSON payload. Edit
`lib/app.dart` to add additional routes, middleware, and providers.

## Auth hooks

The demo wires auth callbacks in `lib/app.dart` and listens to auth events
through the global `EventManager` to mirror the Laravel-style event system.
Use `config/auth.yaml` to tweak session strategy and update age defaults.
