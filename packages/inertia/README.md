# Inertia Dart

Build single page apps without building an API. This package implements the
server-side Inertia protocol for Dart and provides property helpers, SSR
support, and testing utilities. Pair it with a client adapter like
`@inertiajs/react`, `@inertiajs/vue3`, or `@inertiajs/svelte`.

> **New here?** Follow the [Build a Contacts App](https://kingwill101.github.io/docs/inertia_dart/tutorial) tutorial for a hands-on walkthrough using just `dart:io`.
>
> **Using the Routed framework?** See [`routed_inertia`](../routed_inertia) for the framework integration.

## Install

```bash
dart pub add inertia_dart
```

## Start From Scratch With dart:io

If you want the smallest possible setup with a plain `HttpServer`, use this
flow.

1. Create the Dart app and add the server package:

```bash
dart create -t console my_app
cd my_app
dart pub add inertia_dart
```

2. Scaffold the client app and install its dependencies:

```bash
dart run inertia_dart:inertia create client --framework react --package-manager npm
cd client
npm install
cd ..
```

3. Wire the server with the raw `dart:io` helpers:

```dart
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';

const assets = InertiaViteAssets(
  entry: 'index.html',
  manifestPath: 'client/dist/.vite/manifest.json',
  hotFile: 'client/public/hot',
  includeReactRefresh: true,
);

Future<void> main() async {
  final server = await HttpServer.bind('127.0.0.1', 8080);

  await for (final request in server) {
    if (await tryWriteStaticAsset(request, rootDirectory: 'client/dist')) {
      continue;
    }

    if (request.uri.path != '/') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
      await request.response.close();
      continue;
    }

    await respondWithInertiaPage(
      request,
      component: 'Home',
      props: {'title': 'Hello from Dart'},
      html: (page, _) => renderInertiaVitePageHtml(
        page,
        assets: assets,
        title: 'My App',
      ),
    );
  }
}
```

4. Run the server and the Vite client:

```bash
dart run bin/my_app.dart
cd client
npm run dev
```

To add SSR later, start a renderer with `dart run bin/ssr.dart` or
`dart run inertia_dart:inertia ssr:start`, then pass
`ssr: (page) => gateway.render(jsonEncode(page.toJson()))` into
`respondWithInertiaPage()` and forward the SSR payload to
`renderInertiaVitePageHtml(..., ssr: ssr)`.

For a fuller walkthrough, use the [Build a Contacts App](https://kingwill101.github.io/docs/inertia_dart/tutorial)
tutorial. For runnable reference apps, see:
- [`packages/inertia/example/inertia_client_app`](example/inertia_client_app)
- [`packages/inertia/example/inertia_ssr_app`](example/inertia_ssr_app)

## CLI

Scaffold a Vite client with Inertia already wired:

```bash
dart run inertia_dart:inertia create my-app --framework react
```

Install Inertia into an existing Vite project:

```bash
dart run inertia_dart:inertia install --framework react --path ./web
```

## Quickstart

Create a page payload and return an Inertia JSON response from your server
handler.

```dart
import 'package:inertia_dart/inertia_dart.dart';

final context = PropertyContext(headers: requestHeaders);

final page = InertiaResponseFactory().buildPageData(
  component: 'Dashboard',
  props: {
    'user': {'name': 'Ada'},
    'stats': LazyProp(() => loadStats()),
  },
  url: '/dashboard',
  context: context,
  version: '1.0.0',
);

final response = InertiaResponse.json(page);
```

For a full framework integration, see [`packages/routed_inertia`](../routed_inertia).
For working server/client samples, see:
- [`packages/inertia/example/inertia_client_app`](example/inertia_client_app)
- [`packages/inertia/example/inertia_ssr_app`](example/inertia_ssr_app)

## Props

Property helpers let you control when data resolves and how it merges.

- `LazyProp` and `OptionalProp` are excluded from the first load and only
  resolve on partial reloads.
- `DeferredProp` defers evaluation until the client requests the group.
- `MergeProp` supports deep merge, append/prepend paths, and match-on keys.
- `ScrollProp` adds pagination metadata for infinite scroll behavior.
- `OnceProp` adds once metadata with optional TTL and keys.

```dart
final props = {
  'user': () => user,
  'stats': OptionalProp(() => expensiveStats()),
  'feed': DeferredProp(() => loadFeed(), group: 'feed', merge: true)
      .append('items', 'id'),
  'cursor': ScrollProp(() => pageData),
  'token': OnceProp(() => token, ttl: Duration(hours: 1)),
};
```

## Partial Reloads

The request helpers parse advanced Inertia headers:

- `X-Inertia-Partial-Data`
- `X-Inertia-Partial-Except`
- `X-Inertia-Reset`
- `X-Inertia-Except-Once-Props`
- `X-Inertia-Infinite-Scroll-Merge-Intent`
- `X-Inertia-Error-Bag`

Use `InertiaHeaderUtils` or `InertiaRequest` to build the correct
`PropertyContext` for your server.

## History Flags

`PageData` supports history flags:

- `encryptHistory`
- `clearHistory`

## Middleware

Enable history encryption for every response with the built-in middleware:

```dart
final middleware = EncryptHistoryMiddleware();
final response = await middleware.handle(request, (req) async {
  return next(req);
});
```

## SSR

Use `SsrGateway` to call your SSR server and render HTML:

```dart
final gateway = HttpSsrGateway(Uri.parse('http://localhost:13714'));
final ssr = await gateway.render(jsonPage);
```

Control SSR behavior in code with `InertiaSsrSettings`:

```dart
final settings = InertiaSsrSettings(
  enabled: true,
  endpoint: Uri.parse('http://127.0.0.1:13714/render'),
  bundle: 'bootstrap/ssr/ssr.mjs',
  runtime: 'node',
  runtimeArgs: ['--trace-warnings'],
);
```

You can also start/stop/check a local SSR process:

```dart
final process = await startSsrServer(
  SsrServerConfig.fromSettings(settings),
);
final healthy = await checkSsrServer(endpoint: settings.endpoint!);
await stopSsrServer(endpoint: settings.endpoint!);
process.kill();
```

CLI helpers for SSR bundles:

```bash
dart run inertia_dart:inertia ssr:start --runtime node
dart run inertia_dart:inertia ssr:check --url http://127.0.0.1:13714
dart run inertia_dart:inertia ssr:stop --url http://127.0.0.1:13714
```

## Asset Manifest Helper

`InertiaAssetManifest` loads a Vite-style `manifest.json` and renders tags.

```dart
final manifest = await InertiaAssetManifest.load('client/dist/.vite/manifest.json');
final tags = manifest.renderTags('index.html', baseUrl: '/');
```

## Vite Asset Helper

`InertiaViteAssets` reads a dev hot file or a production manifest and returns
script/style tags.

```dart
final assets = InertiaViteAssets(
  entry: 'index.html',
  hotFile: 'client/public/hot',
  manifestPath: 'client/dist/.vite/manifest.json',
  includeReactRefresh: true,
);

final tags = await assets.resolve();
final htmlTags = tags.renderAll();
```

## dart:io HttpServer Helper

If you are using `dart:io` directly, you can keep the setup small without
re-implementing the Inertia protocol branches yourself.

```dart
const assets = InertiaViteAssets(
  entry: 'index.html',
  manifestPath: 'client/dist/.vite/manifest.json',
  hotFile: 'client/public/hot',
  includeReactRefresh: true,
);

if (await tryWriteStaticAsset(httpRequest, rootDirectory: 'client/dist')) {
  return;
}

await respondWithInertiaPage(
  httpRequest,
  component: 'Home',
  props: {'title': 'Inertia + HttpServer'},
  html: (page, _) => renderInertiaVitePageHtml(
    page,
    assets: assets,
    title: 'Inertia + HttpServer',
  ),
);
```

For SSR, add `ssr: (page) => gateway.render(jsonEncode(page.toJson()))` and
pass the resulting payload into `renderInertiaVitePageHtml(..., ssr: ssr)`.

## Vite Hot File Helper

The package ships a small Vite plugin to generate a `public/hot` file (Laravel
style). Copy [`assets/vite/inertia_hot_file.js`](assets/vite/inertia_hot_file.js)
into your project and import it from your Vite config. A full template is
available at [`assets/vite/vite.config.js`](assets/vite/vite.config.js).

```js
import { defineConfig } from 'vite'
import { inertiaHotFile } from './inertia_hot_file.js'

export default defineConfig({
  plugins: [inertiaHotFile()],
})
```

## Testing

Use `AssertableInertia` and `InertiaTestExtensions` for response assertions.

```dart
response.assertInertia((page) {
  page.component('Dashboard').has('user.name');
});
```

## Learn More

- [Inertia Dart docs](https://kingwill101.github.io/docs/inertia_dart/) -- full API reference and tutorial
- [Routed Inertia docs](https://kingwill101.github.io/docs/routed_inertia/) -- framework integration for Routed apps
- [Inertia core docs](https://inertiajs.com) -- protocol specification and client adapters
