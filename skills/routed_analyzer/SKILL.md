---
name: routed-analyzer
description: Maintain, extend, document, test, or troubleshoot the routed_analyzer subsystem in the Routed Dart monorepo. Use when a task touches routed_analyzer APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_analyzer

This skill is the complete working guide for the `routed_analyzer` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_analyzer`
- **Directory:** `packages/routed_analyzer`
- **Version in this checkout:** `0.1.1`
- **Role:** Analyzer plugin and Routed lint rules
- **Purpose:** The Dart analyzer plugin for route schema and validation metadata. It is development-time tooling, not an Engine provider.

### Public API

- `RoutedAnalyzerPlugin` is the analyzer plugin entrypoint.
- The public inspection helpers expose `inspectProviders` and `ProviderMetadata`.
- Rules are `missing_route_schema`, `missing_schema_summary`, `missing_schema_response`, `invalid_validation_rule`, and `schema_deprecated_without_description`.
- The plugin checks route schema metadata, OpenAPI summaries/responses, pipe validation rule names, and deprecation descriptions.

### Public imports

- `package:routed_analyzer/main.dart`
- `package:routed_analyzer/routed_analyzer.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- Activate it in the application or workspace analysis_options.yaml under `plugins`; adding it only to pubspec dependencies is insufficient.
- Restart the analysis server after changing plugin activation.
- Keep analyzer-only dependencies and APIs out of runtime provider registration.

### Known hazards

- Do not turn a lint into a runtime exception or provider.
- Keep rule names stable because analysis_options and CI suppressions refer to them.
- When adding a rule, test both the diagnostic location and the non-diagnostic valid form.

## Minimal usage

```dart
plugins:
  routed_analyzer: ^0.1.0
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_analyzer`.
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

Run analyzer plugin tests and metadata inspection tests; validate activation with the Dart SDK range >=3.9.0 and an analysis server that supports plugins.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_analyzer
dart analyze --fatal-infos packages/routed_analyzer
dart test packages/routed_analyzer/test
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
