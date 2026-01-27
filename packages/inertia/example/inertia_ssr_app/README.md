# Inertia SSR App (dart:io)

This example pairs a minimal Dart `dart:io` server with a Vite Inertia client in `client/` and an SSR entry.

## Server

```bash
dart pub get
dart run bin/ssr.dart
dart run bin/server.dart
```

Defaults:
- `INERTIA_SSR=true`
- `INERTIA_SSR_URL=http://127.0.0.1:13714/render`
- `INERTIA_SSR_PORT=13714`

Set `INERTIA_SSR=false` to disable SSR rendering.

## Client

```bash
cd client
npm run dev
```

To build both client and SSR bundles:

```bash
npm run build
```

## Notes
- The server calls the SSR gateway and injects `head`/`body` into the HTML when available.
