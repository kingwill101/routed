---
name: routed-cli
description: Maintain, extend, document, test, or troubleshoot the routed_cli subsystem in the Routed Dart monorepo. Use when a task touches routed_cli APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_cli

This skill is the complete working guide for the `routed_cli` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_cli`
- **Directory:** `packages/routed_cli`
- **Version in this checkout:** `0.3.0`
- **Role:** Project commands, configuration, development, and deployment tooling
- **Purpose:** The Routed command runtime and project tooling. It owns command registration, project command discovery, development servers, scaffolding, provider commands, route inspection, OpenAPI generation, and deployment orchestration.

### Public API

- `RoutedCommandRunner` is the public command runner.
- `CliLogger`, `CliVersion`, and `DevOptions` provide shared CLI concerns.
- `ProjectCommandsLoader` discovers and proxies application commands.
- `DevServerRunner` runs and watches the application development server.
- `Templates`, `ScaffoldTemplate`, and `scaffoldTemplateBytes` define project scaffolding.
- `ProviderCommandRegistry` and `ProviderArtisanalCommandRegistry` extend provider command surfaces.

### Public imports

- `package:routed_cli/routed_cli.dart`

### Runtime package dependencies

- `routed`
- `routed_analyzer`
- `routed_core`
- `routed_logging`

### Composition rules

- Install as a dev dependency and invoke it with `dart run routed_cli ...`; it is not an Engine provider.
- Generated applications keep typed provider configuration in lib/config.dart and routes in lib/app.dart; the CLI loads createEngine().
- OpenAPI generation consumes the runtime route manifest; deployment commands consume generated project metadata and provider bindings.

### Known hazards

- Preserve dry-run behavior and never write secrets into generated Wrangler or deployment config.
- Keep command names and aliases compatible; canonical OpenAPI invocation is `dart run routed_cli openapi generate`.
- When changing scaffolding, test generated files, imports, formatting, and the follow-up command execution.

## Minimal usage

```dart
dev_dependencies:
  routed_cli: ^0.3.0

Run commands with:
  dart run routed_cli create
  dart run routed_cli dev
  dart run routed_cli openapi generate
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_cli`.
2. Keep the public import names and exported symbols above stable unless the
   task explicitly changes the API. Never document a `lib/src` import.
3. For provider or middleware changes, exercise registration, request-context
   access, the success path, and the failure/reload path.
4. For host or transport changes, test both the value/portable path and the
   streaming/native path where this subsystem supports both.
5. For generated output, make the input contract authoritative and verify the
   generated artifact rather than hand-editing output.
6. Update tests and user-facing package documentation when public behavior
   changes; keep examples aligned with the usage contract above.

### Focused test intent

Cover create templates, command parsing, project command discovery, dev-server lifecycle, provider command registration, OpenAPI generation, and deployment argument validation.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_cli
dart analyze --fatal-infos packages/routed_cli
dart test packages/routed_cli/test
```

Keep this skill's embedded facts synchronized when a public package version,
public barrel, or dependency boundary changes.

## Ecosystem boundary rules

- Applications use `routed` for the full provider catalogue or
  `routed_core` plus explicit adapters for slim compositions.
- Routed adapters depend on `routed_core` and matching `server_*` runtimes;
  they must not depend on the batteries-included `routed` facade.
- Host I/O belongs in `routed_io`, `routed_node`, or `server_native`, not in
  feature adapters.
- Framework-agnostic `server_*` implementations must not import Routed from
  `lib/`.
