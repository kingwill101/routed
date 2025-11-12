# routed

[![Pub Version](https://img.shields.io/pub/v/routed.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/routed)
[![CI](https://github.com/kingwill101/routed/actions/workflows/routed.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/routed.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

`routed` is a modular HTTP engine for Dart with first-class routing, middleware,
configuration, localization, logging, signals, and lifecycle management. It is
the foundation of the routed ecosystem packages published from this repo.

## Highlights

- **Declarative routing** with strongly typed handlers, middleware stacks, and
  lifecycle events (including WebSocket routes).
- **Provider architecture** for configuration, caching, storage, sessions,
  localization, rate limiting, and more.
- **Observability tooling** via contextual logging, signal hubs, and
  event-publishing hooks for instrumentation.
- **Extensible drivers** so you can register custom storage/cache/session
  drivers that plug directly into the CLI helper commands.

## Install

```yaml
dependencies:
  routed: ^0.2.0
```

Then run `dart pub get`.

## Quick start

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = Engine()
    ..get('/', (ctx) => ctx.text('Hello routed!'))
    ..get('/json', (ctx) => ctx.json({'ok': true}))
    ..group('/api', (router) {
      router.post('/users', (ctx) async {
        final body = await ctx.jsonBody();
        return ctx.json({'name': body['name'], 'created': true});
      });
    });

  await engine.initialize();
  await engine.serve(host: '127.0.0.1', port: 8080);
}
```

Browse the `/doc` directory for deeper topics (drivers, events, configuration)
or open the docs published at [docs.routed.dev](https://docs.routed.dev).

## Funding

Help keep the ecosystem maintained by
[buying me a coffee](https://www.buymeacoffee.com/kingwill101).
