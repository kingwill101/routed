/// Observability providers for Routed applications.
///
/// The package combines request tracing, Prometheus metrics, health endpoints,
/// and error observers behind the typed `ObservabilityConfig` API.
library;

export 'src/config.dart';
export 'src/errors.dart';
export 'src/health.dart';
export 'src/metrics.dart';
export 'src/providers/observability.dart' show ObservabilityServiceProvider;
export 'src/register_providers.dart' show registerRoutedObservabilityProviders;
export 'src/tracing.dart';
