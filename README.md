# routed_ecosystem

Workspace for the Routed framework, testing utilities, CLI, Hotwire helpers,
class_view adapters, and runnable examples. The repo uses a Dart monorepo
layout so packages share tooling, CI, and release notes.

## Packages

- [packages/routed](packages/routed) – modular HTTP engine with providers,
  logging, localization, signals, and lifecycle hooks.
- [packages/routed_cli](packages/routed_cli) – project scaffolding,
  configuration docs, provider management, and dev tooling.
- [packages/routed_hotwire](packages/routed_hotwire) – Turbo/Stimulus helpers
  for realtime experiences atop Routed.
- [packages/property_testing](packages/property_testing) – generator + shrinking
  library that powers fuzz/property coverage across the workspace.
- [packages/server_testing/server_testing](packages/server_testing/server_testing) –
  HTTP & browser testing harness with CLI-managed drivers.
- [packages/server_testing/routed_testing](packages/server_testing/routed_testing) –
  Routed transport adapter for `server_testing`.
- [packages/server_testing/server_testing_shelf](packages/server_testing/server_testing_shelf) –
  Shelf adapter for `server_testing`.
- [packages/class_view/class_view](packages/class_view/class_view) – Django-style
  class-based views plus tooling.
- [packages/class_view/routed_class_view](packages/class_view/routed_class_view) –
  Routed adapter for class_view.
- [packages/class_view/shelf_class_view](packages/class_view/shelf_class_view) –
  Shelf adapter for class_view.
- [packages/class_view/class_view_image_field](packages/class_view/class_view_image_field) –
  optional image field extensions.
- [packages/class_view/simple_blog](packages/class_view/simple_blog) &
  [packages/class_view/todo_test](packages/class_view/todo_test) – end-to-end
  samples and acceptance tests.
- [packages/jaspr_routed](packages/jaspr_routed) – jaspr adapter plus
  [example](packages/jaspr_routed/example).

## Examples

Each example lives under `examples/` so you can run it locally:

- [examples/config_demo](examples/config_demo) – configuration + CLI walkthrough.
- [examples/kitchen_sink](examples/kitchen_sink) – broad feature sampler.
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
its own changelog and versioned tags (e.g. `routed_cli-0.2.1+1`).

## Funding

Keep the ecosystem healthy by
[buying Glenford a coffee](https://www.buymeacoffee.com/kingwill101).
