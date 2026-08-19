---
name: routed
description: Maintain, extend, document, test, or troubleshoot the routed subsystem in the Routed Dart monorepo. Use when a task touches routed APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed

This skill is the complete working guide for the `routed` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed`
- **Directory:** `packages/routed`
- **Version in this checkout:** `0.5.0`
- **Role:** Batteries-included framework facade and official provider catalogue
- **Purpose:** The batteries-included application facade. It re-exports core and the official feature adapters, and exposes the one-time provider registration helper.

### Public API

- `registerRoutedProviders()` registers the official provider catalogue; call it once before `Engine.create()`.
- `Engine.create()` then boots the core plus registered feature providers.
- The facade exports routed_core, routed_auth, routed_cache, routed_sessions, routed_storage, routed_rate_limit, routed_views, routed_http, routed_logging, routed_observability, routed_openapi, routed_security, and routed_validation.
- Typed provider constructors own feature configuration; there is no YAML or dotted-key configuration surface.

### Public imports

- `package:routed/routed.dart`

### Runtime package dependencies

- `routed_auth`
- `routed_cache`
- `routed_core`
- `routed_http`
- `routed_logging`
- `routed_observability`
- `routed_openapi`
- `routed_rate_limit`
- `routed_security`
- `routed_sessions`
- `routed_storage`
- `routed_validation`
- `routed_views`

### Composition rules

- Use this package for normal applications that want the official provider set.
- For a slim app, use routed_core and add only the adapters needed; do not make adapters depend on this facade.
- When adding a provider to the official bundle, update the export, registration order, provider-count expectations, and a facade bootstrap test.

### Known hazards

- Do not register the catalogue after engine creation; late registration does not retroactively boot providers.
- Do not hide typed provider configuration behind a new global config format.
- Keep host transport separate: VM serving uses routed_io, while JavaScript hosts use routed_node.

## Minimal usage

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  registerRoutedProviders();
  final engine = await Engine.create();
  engine.get('/health', (ctx) => ctx.json({'ok': true}));
  await engine.serve(port: 8080);
}
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed`.
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

Exercise a minimal health route, provider registration before engine creation, and a second explicit-provider composition for any catalogue change.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed
dart analyze --fatal-infos packages/routed
dart test packages/routed/test
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
