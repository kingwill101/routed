---
name: routed-logging
description: Maintain, extend, document, test, or troubleshoot the routed_logging subsystem in the Routed Dart monorepo. Use when a task touches routed_logging APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_logging

This skill is the complete working guide for the `routed_logging` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_logging`
- **Directory:** `packages/routed_logging`
- **Version in this checkout:** `0.2.0`
- **Role:** HTTP logging provider and request logger helpers
- **Purpose:** The HTTP logging provider and request logger surface. It installs RoutedLogger, logging context, driver registration, and stderr/null/file drivers.

### Public API

- `LoggingServiceProvider` installs logging services; `registerRoutedLoggingProviders()` registers the package provider catalogue.
- `LoggingConfig` controls typed provider configuration such as `errorsOnly`.
- `RoutedLogger`, `LoggingContext`, and `ctx.logger` provide request-scoped logging.
- `LogDriverRegistry`, `LogDriverRegistration`, `StderrLogDriver`, `NullLogDriver`, and `SingleFileLogDriver` define output drivers.
- The package re-exports selected routed_core logging/config contracts needed to integrate the provider.

### Public imports

- `package:routed_logging/routed_logging.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- The routed facade includes logging after `registerRoutedProviders()`.
- A slim engine adds `LoggingServiceProvider()` or a typed `LoggingConfig` instance to its provider list.
- Keep driver construction and validation explicit; do not introduce an implicit global logger.

### Known hazards

- Configuration is typed and fixed at engine startup; there is no YAML/dotted-key logging path.
- Do not leak request secrets or authorization headers into log records.
- Preserve errorsOnly and request-context behavior when changing driver dispatch.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_logging/routed_logging.dart';

final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  LoggingServiceProvider(LoggingConfig(errorsOnly: true)),
]);
engine.get('/health', (ctx) { ctx.logger.info('health'); return ctx.json({'ok': true}); });
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_logging`.
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

Cover provider boot, context logger access, driver registration/validation, stderr/null/file output, errorsOnly filtering, and request correlation.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_logging
dart analyze --fatal-infos packages/routed_logging
dart test packages/routed_logging/test
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
