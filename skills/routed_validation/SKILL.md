---
name: routed-validation
description: Maintain, extend, document, test, or troubleshoot the routed_validation subsystem in the Routed Dart monorepo. Use when a task touches routed_validation APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_validation

This skill is the complete working guide for the `routed_validation` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_validation`
- **Directory:** `packages/routed_validation`
- **Version in this checkout:** `0.1.0`
- **Role:** Validation rules and validation utilities
- **Purpose:** Validation primitives and rule implementations for Routed. It is on-demand and does not register an Engine service provider.

### Public API

- `Validator.make(rules, registry: ...)` builds a validator from pipe expressions such as `required|email|min_length:2`.
- `ValidationRule`, `AbstractValidationRule`, and `ContextAwareValidationRule` define rule contracts.
- `ValidationRuleRegistry`, `ValidationRuleFactory`, `requireValidationRegistry`, and `ValidationContext` manage rule lookup/context.
- The public rule catalogue covers required/nullable, string/numeric/array/file rules, comparisons, formats, IP/JSON, and collection rules.
- `ValidationFile` and file rules support upload-aware validation without coupling the validator to a concrete filesystem.

### Public imports

- `package:routed_validation/routed_validation.dart`

### Runtime package dependencies

- `routed_core`
- `routed_http`

### Composition rules

- Create the registry on demand from the initialized engine container; there is no provider boot step.
- Use routed_validation from a routed app or directly with routed_core request data.
- Add a custom rule through the registry/factory contract and keep context-aware rules explicit about required context.

### Known hazards

- Preserve rule names and option parsing because routed_analyzer validates pipe rule names statically.
- Do not make validation silently mutate input or conflate absent, null, empty, and invalid values.
- Test rule messages/options, registry lookup, context-aware behavior, and file metadata limits.

## Minimal usage

```dart
import 'package:routed_validation/routed_validation.dart';

final validator = Validator.make({'email': 'required|email', 'name': 'required|min_length:2'}, registry: ValidationRuleRegistry.defaults());
final errors = validator.validate({'email': 'a@example.com', 'name': 'Ada'});
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_validation`.
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

Cover validator parsing, registry lookup, scalar/array/file rules, comparison rules, context-aware rules, invalid options, and error collection.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_validation
dart analyze --fatal-infos packages/routed_validation
dart test packages/routed_validation/test
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
