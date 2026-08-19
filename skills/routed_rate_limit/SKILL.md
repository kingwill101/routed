---
name: routed-rate-limit
description: Maintain, extend, document, test, or troubleshoot the routed_rate_limit subsystem in the Routed Dart monorepo. Use when a task touches routed_rate_limit APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_rate_limit

This skill is the complete working guide for the `routed_rate_limit` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_rate_limit`
- **Directory:** `packages/routed_rate_limit`
- **Version in this checkout:** `0.1.0`
- **Role:** Rate-limit service and middleware integration
- **Purpose:** The Routed adapter for server_rate_limit. It binds a rate-limit service to EngineContext, a typed provider, middleware, and rate-limit events.

### Public API

- `RoutedRateLimitProvider(RateLimitConfig(service: ...))` installs the service.
- `rateLimitMiddleware(service)` applies limits to selected routes or middleware stacks.
- `RateLimitEngineContext` exposes the service through the request context.
- The barrel re-exports server_rate_limit contracts and the Routed rate-limit event types.
- Provider IDs and configuration are typed; the full facade can register the official provider.

### Public imports

- `package:routed_rate_limit/routed_rate_limit.dart`

### Runtime package dependencies

- `routed_core`
- `server_auth`
- `server_rate_limit`

### Composition rules

- Construct the framework-agnostic service in server_rate_limit, then pass it to the provider and middleware.
- Use `registerRoutedProviders()` in a batteries-included app or add `RoutedRateLimitProvider` explicitly in a slim engine.
- Keep key extraction, window algorithm, storage, and service policy in server_rate_limit.

### Known hazards

- Apply middleware at the intended scope; provider installation alone does not necessarily limit every route.
- Preserve response headers/status and retry metadata for denied requests.
- Test concurrency, reset windows, backend errors, and identity/key normalization.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:server_rate_limit/server_rate_limit.dart';

final service = RateLimitService(const []);
final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  RoutedRateLimitProvider(RateLimitConfig(service: service)),
]);
engine.get('/limited', handler, middlewares: [rateLimitMiddleware(service)]);
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_rate_limit`.
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

Cover provider config, context access, middleware allow/deny paths, rate-limit events, service backend behavior, and boundary responses.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_rate_limit
dart analyze --fatal-infos packages/routed_rate_limit
dart test packages/routed_rate_limit/test
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
