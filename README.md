# routed_ecosystem

[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![Docs](https://img.shields.io/badge/docs-routed.dev-4f46e5)](https://docs.routed.dev)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Support](https://img.shields.io/badge/support-Buy%20Me%20a%20Coffee-ff813f?logo=buymeacoffee)](https://www.buymeacoffee.com/kingwill101)

Workspace for the Routed framework, testing utilities, CLI, Hotwire helpers,
server testing adapters, and runnable examples. The repo uses a Dart monorepo
layout so packages share tooling, CI, and release notes.

## Packages

The complete package list, current versions, and package roles are maintained
in the [Routed package catalog](docs/package-catalog.md).

- [packages/routed](packages/routed) – modular HTTP engine with providers,
  logging, localization, signals, and lifecycle hooks.
- [packages/routed_cli](packages/routed_cli) – project scaffolding,
  configuration docs, provider management, and dev tooling.
- [packages/routed_hotwire](packages/routed_hotwire) – Turbo/Stimulus helpers
  for realtime experiences atop Routed.
- [packages/server_testing/routed_testing](packages/server_testing/routed_testing) –
  Routed transport adapter for `server_testing`.

## Routed application setup

For a standard application, import the public `routed` facade and initialize
the engine asynchronously. The facade registers the official provider
catalogue before `Engine.create()` boots it:

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = await Engine.create();
  engine.get('/health', (ctx) => ctx.json({'ok': true}));
  await engine.serve(port: 8080);
}
```

When composing a slim application, use `routed_core` and add each feature
provider explicitly, for example `RoutedSessionsProvider` together with
`sessionMiddleware` from `routed_sessions`. Feature packages document their
provider and middleware setup individually.

Testing utilities that were extracted into their own repositories (published
under the [RoutedDart](https://github.com/RoutedDart) organization):

- [`property_testing`](https://github.com/RoutedDart/property_testing) –
  generator + shrinking library that powers fuzz/property coverage.
- [`server_testing`](https://github.com/RoutedDart/server_testing) – HTTP &
  browser testing harness with CLI-managed drivers, plus the
  `server_testing_shelf` Shelf adapter.

## Examples

Each example lives under `examples/` so you can run it locally:

- [examples/config_demo](examples/config_demo) – configuration + CLI walkthrough.
- [examples/kitchen_sink](examples/kitchen_sink) – broad feature sampler.
- [examples/openapi_demo](examples/openapi_demo) – OpenAPI manifest generation example.
- [examples/localization](examples/localization) – translation provider demo.
- [examples/multipart](examples/multipart) – upload + binding helpers.
- [examples/liquid_template](examples/liquid_template) – template rendering.
- [examples/http2](examples/http2) – TLS + HTTP/2 bootstrap.
- [examples/oauth_keycloak](examples/oauth_keycloak) – OAuth/Keycloak flow.
- [examples/forward_proxy](examples/forward_proxy),
  [examples/fallback](examples/fallback),
  [examples/route_events](examples/route_events),
  [examples/project_commands_demo](examples/project_commands_demo), and other
  folders cover additional routing/CLI scenarios.

## Development

```bash
dart pub get      # fetch workspace dependencies
melos bootstrap   # (if you prefer melos commands)
dart format .     # keep formatting consistent
dart test ./...   # run package tests
```

Publishing instructions live in `docs/publishing-checklist.md`. Each package has
its own changelog and versioned tags (e.g. `routed_cli-0.1.0`).

## Funding

Keep the ecosystem healthy by
[buying me a coffee](https://www.buymeacoffee.com/kingwill101).
