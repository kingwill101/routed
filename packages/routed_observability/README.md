# routed_observability

Observability providers/middleware for Routed (tracing, metrics, health).

Provides the health, metrics, tracing, and error-observer integration for a
Routed engine.

## Install
```yaml
dependencies:
  routed: ^0.4.0
  routed_core: ^0.3.3
  routed_observability: ^0.1.0
```

## Initialize the provider

The package exposes `ObservabilityServiceProvider`. The full `routed` facade
registers it automatically; a slim application adds it explicitly:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_observability/routed_observability.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      ObservabilityServiceProvider(
        ObservabilityConfig(
          metrics: ObservabilityMetricsConfig(enabled: true),
          health: ObservabilityHealthConfig(enabled: true),
        ),
      ),
    ],
  );

  // Health defaults to /readyz and /livez; metrics use /metrics when enabled.
  await engine.serve(port: 8080);
}
```

The provider supplies health, metrics, tracing, and error-observer services and
connects their configured middleware. Configuration is validated before
provider boot and remains fixed for the lifetime of the engine. The registry
helper is retained only for discovering the default provider in the facade;
custom configuration should be passed to `ObservabilityServiceProvider`.
