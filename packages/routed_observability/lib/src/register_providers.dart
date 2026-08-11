import 'package:routed_core/providers.dart' show ProviderRegistry;

import 'providers/observability.dart';

/// Registers observability providers for `http.providers` resolution.
void registerRoutedObservabilityProviders() {
  ProviderRegistry.instance.register(
    'routed.observability',
    factory: ObservabilityServiceProvider.new,
    description: 'Tracing, metrics, health, and error observers.',
  );
}
