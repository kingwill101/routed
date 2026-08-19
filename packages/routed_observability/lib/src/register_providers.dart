import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'providers/observability.dart';

/// Registers observability provider factories in the shared registry.
void registerRoutedObservabilityProviders() {
  ProviderRegistry.instance.register(
    'routed.observability',
    factory: ObservabilityServiceProvider.new,
    description: 'Tracing, metrics, health, and error observers.',
  );
}
