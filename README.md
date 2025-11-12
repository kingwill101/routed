# routed_ecosystem

Workspace for the Routed framework, testing utilities, CLI, Hotwire helpers,
class_view adapters, and runnable examples. The repo uses a Dart monorepo
layout so packages share tooling, CI, and release notes.

## Packages

- `packages/routed` – modular HTTP engine with providers, logging, and
  localization built in.
- `packages/server_testing/*` – HTTP/browser testing harness, Routed adapters,
  and Shelf bridge.
- `packages/property_testing` – property-based generator suite used across the
  workspace.
- `packages/routed_cli` – project scaffolding, config generation, and dev tools.
- `packages/class_view/*` – Django-style view system plus adapters for Routed
  and Shelf.
- `packages/routed_hotwire` – Turbo/Stimulus helpers.
- `packages/jaspr_routed` – jaspr adapter + example.
- `examples/*` – runnable servers that showcase specific features (config,
  localization, multipart uploads, etc.).

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
