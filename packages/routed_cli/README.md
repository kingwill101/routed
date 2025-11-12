# routed_cli

[![Pub Version](https://img.shields.io/pub/v/routed_cli.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/routed_cli)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://github.com/sponsors/kingwill101)

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

## Install

```yaml
dev_dependencies:
  routed_cli: ^0.2.1
```

Add the executable to your `dev_dependencies` and invoke it via `dart run`.
Prefer the global install (`dart pub global activate routed_cli`) when you want
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
dart run routed_cli create demo_api --template api
cd demo_api
dart run routed config:init
dart run routed dev
```

See `lib/src/args/commands` and the tests under `test/` for more examples.

## Funding

Like the tooling? [Sponsor @kingwill101](https://github.com/sponsors/kingwill101)
to help keep releases and new commands flowing.***
