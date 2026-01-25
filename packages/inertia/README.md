# Inertia Dart

Build single page apps without building an API. This package implements the
server-side Inertia protocol for Dart and provides property helpers, SSR
support, and testing utilities. Pair it with a client adapter like
`@inertiajs/react`, `@inertiajs/vue3`, or `@inertiajs/svelte`.

## Install

```bash
dart pub add inertia_dart
```

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
import 'package:inertia_dart/inertia.dart';

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

For a full framework integration, see `packages/routed_inertia`.

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
final manifest = await InertiaAssetManifest.load('build/manifest.json');
final tags = manifest.renderTags('resources/js/app.js', baseUrl: '/');
```

## Vite Asset Helper

`InertiaViteAssets` reads a dev hot file or a production manifest and returns
script/style tags.

```dart
final assets = InertiaViteAssets(
  entry: 'src/main.jsx',
  hotFile: 'client/public/hot',
  manifestPath: 'client/dist/.vite/manifest.json',
  includeReactRefresh: true,
);

final tags = await assets.resolve();
final htmlTags = tags.renderAll();
```

## dart:io HttpServer Helper

If you are using `dart:io` directly, you can build requests and write responses
without a framework wrapper.

```dart
final request = inertiaRequestFromHttp(httpRequest);
final context = request.createContext();
final page = InertiaResponseFactory().buildPageData(
  component: 'Home',
  props: {'title': 'Inertia + HttpServer'},
  url: request.url,
  context: context,
);

final response = InertiaResponse.json(page);
await writeInertiaResponse(httpRequest.response, response);
```

## Vite Hot File Helper

The package ships a small Vite plugin to generate a `public/hot` file (Laravel
style). Copy `assets/vite/inertia_hot_file.js` into your project and import it
from your Vite config. A full template is available at
`assets/vite/vite.config.js`.

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

- Inertia core docs: https://inertiajs.com
