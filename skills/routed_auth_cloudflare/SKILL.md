---
name: routed-auth-cloudflare
description: Maintain, extend, document, test, or troubleshoot the routed_auth_cloudflare subsystem in the Routed Dart monorepo. Use when a task touches routed_auth_cloudflare APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_auth_cloudflare

This skill is the complete working guide for the `routed_auth_cloudflare` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_auth_cloudflare`
- **Directory:** `packages/routed_auth_cloudflare`
- **Version in this checkout:** `0.1.0`
- **Role:** Durable Cloudflare D1 `AuthStore` adapter and typed migrations
- **Purpose:** Durable Cloudflare D1 AuthStore persistence for Routed applications.

### Public API

- Use the public package barrel and the exported API surface shown below.

### Public imports

- `package:routed_auth_cloudflare/routed_auth_cloudflare.dart`

### Runtime package dependencies

- `routed_node`
- `server_auth`

### Composition rules

- Keep framework integration in this routed package and framework-agnostic behavior in its server_* dependency.

### Known hazards

- Preserve public exports, dependency direction, and existing behavior.

## Minimal usage

```dart
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_auth_cloudflare`.
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

Run the focused package tests and add a regression test for changed behavior.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_auth_cloudflare
dart analyze --fatal-infos packages/routed_auth_cloudflare
dart test packages/routed_auth_cloudflare/test
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
