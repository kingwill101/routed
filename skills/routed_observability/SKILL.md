---
name: routed-observability
description: Maintain, extend, document, test, or troubleshoot the routed_observability subsystem in the Routed Dart monorepo. Use when a task touches routed_observability APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# routed_observability

This skill is the complete working guide for the `routed_observability` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** `routed_observability`
- **Directory:** `packages/routed_observability`
- **Version in this checkout:** `0.1.0`
- **Role:** Health, metrics, tracing, and error observation
- **Purpose:** Health, metrics, tracing, and error-observer integration for Routed. It provides one typed provider and services for operational endpoints and telemetry.

### Public API

- `ObservabilityServiceProvider` installs observability services and configured middleware.
- `ObservabilityConfig` contains tracing, metrics, health, errors, and Sentry configuration objects.
- `HealthService`, `HealthCheck`, `HealthCheckResult`, `HealthResponse`, and `HealthEndpointRegistry` implement health checks/endpoints.
- `MetricsService` provides counters/histograms; `TracingService` and tracing config integrate OpenTelemetry-compatible spans.
- `ErrorObserverRegistry` handles configured error observation; `registerRoutedObservabilityProviders()` registers the default provider.
- Default health endpoints are `/readyz` and `/livez`; metrics use `/metrics` when enabled.

### Public imports

- `package:routed_observability/routed_observability.dart`

### Runtime package dependencies

- `routed_core`

### Composition rules

- The routed facade registers the provider; slim apps add `ObservabilityServiceProvider(ObservabilityConfig(...))` explicitly.
- Configuration is validated before provider boot and fixed for engine lifetime.
- Keep telemetry failure isolated from request correctness: an exporter or observer failure must not replace the application response.

### Known hazards

- Do not expose health or metrics endpoints without considering access policy and information disclosure.
- Preserve disabled-by-default behavior for optional exporters and avoid recording raw sensitive payloads.
- Test health failure status, metric cardinality, trace propagation, and observer exception isolation.

## Minimal usage

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_observability/routed_observability.dart';

final engine = await Engine.create(providers: [
  ...Engine.defaultProviders,
  ObservabilityServiceProvider(ObservabilityConfig(
    metrics: ObservabilityMetricsConfig(enabled: true),
    health: ObservabilityHealthConfig(enabled: true),
  )),
]);
```

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to `routed_observability`.
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

Cover config validation, provider registration, health readiness/liveness, metrics counters/histograms, trace headers/spans, error observers, and endpoint responses.

## Focused validation

```bash
dart format --output=none --set-exit-if-changed packages/routed_observability
dart analyze --fatal-infos packages/routed_observability
dart test packages/routed_observability/test
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
