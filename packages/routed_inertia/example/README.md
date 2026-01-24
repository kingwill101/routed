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

Start the Routed server in another terminal:

```bash
dart run packages/routed_inertia/example/server.dart
```

Visit:
- http://localhost:8080

## Server usage

The example uses the `EngineContext` extension helper:

```dart
engine.get('/', (ctx) {
  return ctx.inertia(
    'Home',
    props: {'title': 'Routed + Inertia'},
    version: version,
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
