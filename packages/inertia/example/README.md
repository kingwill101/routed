# Inertia Dart Examples

This directory contains two Dart server projects, each with a nested Inertia client app in `client/` created via the Inertia CLI.

## Client-only app

Path: `packages/inertia/example/inertia_client_app`

Server:

```bash
cd packages/inertia/example/inertia_client_app
dart pub get
dart run bin/server.dart
```

Client:

```bash
cd packages/inertia/example/inertia_client_app/client
npm run dev
```

Notes:
- Uses a dart:io server and renders Inertia HTML for initial visits.
- No SSR entry in the client project.

## SSR app

Path: `inertia_ssr_app`

Server:

```bash
cd inertia_ssr_app
dart pub get
dart run bin/ssr.dart
dart run bin/server.dart
```

Client:

```bash
cd inertia_ssr_app/client
npm run dev
```

Notes:
- Includes `client/src/ssr.jsx` and SSR build scripts.
- The SSR process is started with `dart run bin/ssr.dart`.
- The Dart server calls the SSR gateway at `INERTIA_SSR_URL` (default `http://127.0.0.1:13714/render`).
- Set `INERTIA_SSR=false` to disable SSR rendering.
