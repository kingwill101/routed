# Routed Inertia

Routed integration for Inertia.js. This package wires the Inertia protocol into
the Routed framework with middleware, `EngineContext` helpers, SSR support, and
template rendering.

> **New here?** Follow the [Build a Todo App](https://kingwill101.github.io/docs/routed_inertia/tutorial) tutorial for a hands-on walkthrough.
>
> **Using dart:io without Routed?** See [`inertia_dart`](../inertia) for the standalone package and its [Contacts App tutorial](https://kingwill101.github.io/docs/inertia_dart/tutorial).

## Install

```bash
dart pub add routed_inertia
```

## Setup

Add the middleware to your engine and render pages with `ctx.inertia`.

```dart
import 'package:routed/routed.dart';
import 'package:routed/providers.dart';
import 'package:routed_inertia/routed_inertia.dart';

final engine = Engine(
  options: [
    withMiddleware([
      RoutedInertiaMiddleware(versionResolver: () => '1.0.0').call,
    ]),
  ],
);

engine.get('/dashboard', (ctx) {
  return ctx.inertia(
    'Dashboard',
    props: {'user': {'name': 'Ada'}},
  );
});
```

## Config-Driven Setup

Register the provider with the routed registry and enable it in config.

```dart
import 'package:routed/routed.dart';
import 'package:routed_inertia/routed_inertia.dart';

registerRoutedInertiaProvider(ProviderRegistry.instance);
```

If you need a custom version resolver, register the provider directly:

```dart
final engine = Engine(
  providers: [
    CoreServiceProvider.withLoader(
      ConfigLoader.yaml(configDirectory: 'config'),
    ),
    InertiaServiceProvider(versionResolver: () => '1.0.0'),
  ],
);
```

```yaml
# config/http.yaml
providers:
  - routed.inertia
```

```yaml
# config/inertia.yaml
version: "1.0.0"
root_view: "inertia/app"
history:
  encrypt: false
ssr:
  enabled: false
  url: "http://127.0.0.1:13714"
  ensure_bundle_exists: true
  runtime: "node"
assets:
  manifest_path: "client/dist/.vite/manifest.json"
  entry: "index.html"
  base_url: "/"
  hot_file: "client/public/hot"
```

When configured, `ctx.inertia` will pull defaults for `version`, `root_view`,
history encryption, and SSR from this config.

When running Vite in dev mode, writing a `hot` file (like `public/hot`) lets the
server auto-detect the dev server URL.

## Shared Props

```dart
engine.get('/shared', (ctx) {
  ctx.inertiaShare({'appName': 'Routed'});
  return ctx.inertia('Shared', props: {'user': 'Ada'});
});
```

## Flash + Errors

```dart
engine.post('/save', (ctx) {
  ctx.inertiaFlash('notice', 'Saved');
  ctx.inertiaErrors({'email': 'Required'});
  return ctx.redirect('/form');
});
```

Select error bags with `X-Inertia-Error-Bag` from the client.

## SSR + Templates

Render HTML through a template or a custom HTML builder, and optionally call
the SSR gateway.

```dart
engine.get('/', (ctx) {
  return ctx.inertia(
    'Home',
    props: {'title': 'Hello'},
    templateName: 'inertia/app',
    ssrEnabled: true,
    ssrGateway: HttpSsrGateway(Uri.parse('http://localhost:13714')),
  );
});
```

## Asset Manifest Helper

Use the core manifest helper to render asset tags.

```dart
final manifest = await InertiaAssetManifest.load('client/dist/.vite/manifest.json');
final tags = manifest.renderTags('index.html', baseUrl: '/');
```

Inject the tags in your template or HTML builder.

## Testing

Use `routed_testing` to assert Inertia responses in integration tests.

```dart
response.assertInertia((page) {
  page.component('Dashboard').has('user.name');
});
```

## Example App

See `packages/routed_inertia/example/README.md` for a full React + Routed demo.

## Learn More

- [Routed Inertia docs](https://kingwill101.github.io/docs/routed_inertia/) -- full reference and tutorial
- [Inertia Dart docs](https://kingwill101.github.io/docs/inertia_dart/) -- standalone package API and dart:io tutorial
- [Inertia.js docs](https://inertiajs.com) -- protocol specification and client adapters
