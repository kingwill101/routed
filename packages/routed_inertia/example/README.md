# Routed Inertia + React Example

This example demonstrates a simple Routed server that renders Inertia responses
and a React frontend powered by `@inertiajs/react`.

## Prerequisites
- Dart SDK 3.9+
- Node.js 18+

## Setup

From the repository root:

```bash
dart pub get
```

Install frontend dependencies:

```bash
cd packages/routed_inertia/example/client
npm install
```

## Run

Start the React dev server:

```bash
cd packages/routed_inertia/example/client
npm run dev
```

The Vite dev server writes `packages/routed_inertia/example/client/public/hot`.
If you want to override the URL, set `INERTIA_DEV_SERVER_URL` (or
`VITE_DEV_SERVER_URL`):

```bash
export INERTIA_DEV_SERVER_URL="http://localhost:5173"
```

Start the Routed app in another terminal:

```bash
cd packages/routed_inertia/example/routed_app/routed_inertia_example
dart run routed dev
```

The example app loads config from `packages/routed_inertia/example/routed_app/`
`routed_inertia_example/config`. Update `config/inertia.yaml` to change the
version, SSR, or asset settings.

Visit:
- http://localhost:8080

## Server usage

The example uses the `EngineContext` extension helper:

```dart
engine.get('/', (ctx) {
  return ctx.inertia(
    'Home',
    props: {'title': 'Routed + Inertia'},
    htmlBuilder: htmlBuilder,
  );
});
```

If you want to render via the configured view engine (e.g. Liquify),
pass a template name or template content:

```dart
return ctx.inertia(
  'Home',
  props: {'title': 'Routed + Inertia'},
  templateName: 'inertia/home',
);
```

## Production Build

Build frontend assets:

```bash
cd packages/routed_inertia/example/client
npm run build
```

Run the server with the production flag so it loads the Vite manifest:

```bash
INERTIA_DEV=false dart run packages/routed_inertia/example/server.dart
```

This will serve `/assets/*` from `packages/routed_inertia/example/client/dist/assets`
and inject the correct hashed bundle paths.
