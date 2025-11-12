# routed_cli

Command-line tooling for the Routed framework. It scaffolds projects, manages
providers and middleware, generates configuration defaults, and offers helpers
for local dev workflows.

## Install

```yaml
dev_dependencies:
  routed_cli: ^0.2.0
```

Add the executable to your `dev_dependencies` and invoke it via `dart run` (or
install globally with `dart pub global activate routed_cli`).

## Commands

- `routed create <name>` – scaffold API/web/fullstack templates with env files
  and starter tests.
- `routed config:init` – write config stubs using Routed’s provider defaults.
- `routed provider:list --config` – inspect enabled providers and their config
  docs.
- `routed dev` – run the development server with auto-restart hooks.

See `lib/src/args/commands` and the tests under `test/` for more examples.***
