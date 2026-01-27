# Inertia Client App (dart:io)

This example pairs a minimal Dart `dart:io` server with a Vite Inertia client in `client/`.

## Server

```bash
dart pub get
dart run bin/server.dart
```

The server listens on `http://127.0.0.1:8080` by default.

## Client

```bash
cd client
npm run dev
```

## Notes
- The server renders initial HTML with `data-page` and injects Vite tags.
- This example is client-only (no SSR entry).
