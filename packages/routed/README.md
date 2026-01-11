# routed

[![Pub Version](https://img.shields.io/pub/v/routed.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/routed)
[![CI](https://github.com/kingwill101/routed/actions/workflows/routed.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/routed.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/support-Buy%20Me%20a%20Coffee-ff813f?logo=buymeacoffee)](https://www.buymeacoffee.com/kingwill101)

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
  final engine = await Engine.create();
  engine
    ..get('/', (ctx) => ctx.text('Hello routed!'))
    ..get('/json', (ctx) => ctx.json({'ok': true}))
    ..group('/api', (router) {
      router.post('/users', (ctx) async {
        final body = await ctx.jsonBody();
        return ctx.json({'name': body['name'], 'created': true});
      });
    });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
```

## Auth

Use `package:routed/auth.dart` for auth providers, routes, and middleware.

```dart
import 'package:routed/auth.dart';
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = await Engine.create();
  engine.container.instance<AuthOptions>(
    AuthOptions(
      providers: [
        CredentialsProvider(
          authorize: (ctx, provider, credentials) async {
            if (credentials.password == 'secret') {
              return AuthUser(id: 'user-1', email: credentials.email);
            }
            return null;
          },
        ),
      ],
      sessionStrategy: AuthSessionStrategy.session,
    ),
  );

  await engine.serve(host: '127.0.0.1', port: 8080);
}
```

## Coverage

Latest local coverage: 61.9% line coverage.

```bash
dart test --coverage=coverage
dart pub run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --package=. --report-on=lib
```

## Cli tooling

Routed provides cli tooling
Command-line tooling for the Routed framework. It scaffolds projects, manages
providers and middleware, generates configuration defaults, and offers helpers
for local dev workflows.

## Highlights

- **Scaffolding templates** for API, web, and full-stack apps with matching
  tests and env files.
- **Config generation** powered by Routed’s provider snapshots, so stubs always
  match the latest defaults.
- **Provider + middleware management** including manifest edits and config doc
  rendering.
- **Developer ergonomics** such as the `dev` command for restart loops and
  tooling that mirrors the production CLI.


Add the executable to your `dev_dependencies` and invoke it via `dart run`.
Prefer the global install (`dart pub global activate routed`) when you want
the `routed` command everywhere.

## Commands

- `routed create <name>` – scaffold API/web/fullstack templates with env files
  and starter tests.
- `routed config:init` – write config stubs using Routed’s provider defaults.
- `routed provider:list --config` – inspect enabled providers and their config
  docs.
- `routed dev` – run the development server with auto-restart hooks.

### Example

```bash
dart run routed create demo_api --template api
cd demo_api
dart run routed config:init
dart run routed dev
```

See `lib/src/args/commands` and the tests under `test/` for more examples.



Browse the `/doc` directory for deeper topics (drivers, events, configuration)
or open the docs published at [docs.routed.dev](https://docs.routed.dev).

## Funding

Help keep the ecosystem maintained by
[buying me a coffee](https://www.buymeacoffee.com/kingwill101).
