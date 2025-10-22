# Routed

Routed is a production-ready HTTP engine for Dart. It combines a fast router, composable middleware pipeline, pluggable service providers, and rich configuration primitives so you can ship APIs, dashboards, and realtime services without stitching together half a dozen libraries.

## Highlights
- Hierarchical routing with typed parameters, trailing-slash management, and automatic OPTIONS and 405 handling.
- Structured middleware layers (global, group, route) plus a manifest-driven registry that providers can extend.
- Integrated session, JWT, and OAuth2 authentication helpers, cache/storage abstractions, and file uploads.
- HTTP/1.1 and HTTP/2 serving, WebSocket handling, SSE helpers, graceful shutdown, and request tracking.
- Observability hooks for logging, metrics, tracing, and health checks out of the box.

## Quick Start
```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = Engine(
    middlewares: [
      loggingMiddleware(),
      timeoutMiddleware(const Duration(seconds: 30)),
    ],
  );

  engine.get('/hello/{name}', (ctx) async {
    final name = ctx.mustGetParam<String>('name');
    return ctx.json({'message': 'Hello $name'});
  }).name('hello.show');

  engine.group(
    path: '/api',
    middlewares: [requireAuthenticated()],
    builder: (router) {
      router.post('/orders', createOrder);
      router.get('/orders/{id:int}', showOrder);
    },
  );

  await engine.serve(port: 8080);
}
```

## Configuration
- **Code first**: pass `EngineConfig` and `EngineOpt` instances directly when constructing the engine.
- **Manifest driven**: drop YAML/JSON configs in `config/` and let the loader merge environments, override via `.env`, and reload at runtime.
- **Providers**: register service providers to contribute defaults, middleware, or background services. Custom providers can be scaffolded with `routed_cli`.

## Packages in This Repository
- `packages/routed` – core engine, router, middleware, providers, and utilities.
- `packages/routed_cli` – project scaffolding, driver generators, and release tooling.
- `packages/routed_testing` / `packages/server_testing` – HTTP and engine test harnesses.
- `packages/property_testing`, `packages/class_view`, `packages/jaspr_routed` – integration layers and experimental tooling.

Examples covering cookies, config hot reloads, template engines, SSE, and more live under `examples/`.

## Documentation
Rendered docs are in `docs/` and published to <https://routed.dev>. Run `npm install && npm run dev` inside that directory to preview changes locally.

## Contributing
1. Install the Dart SDK (>= 3.9.0) and run `dart pub get` from the repo root.
2. Format and lint with `dart format .` and `dart analyze`.
3. Run the full suite with `dart test packages/routed`.

Bug reports and pull requests are welcome. Please include tests when practical.

## License
Licensed under the MIT License. See [LICENSE](LICENSE).
