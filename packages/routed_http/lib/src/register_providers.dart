import 'package:routed_core/providers.dart' show ProviderRegistry;

import 'providers/compression.dart';

/// Registers HTTP-related providers for direct `routed_http` users.
void registerRoutedHttpProviders() {
  ProviderRegistry.instance.register(
    'routed.compression',
    factory: RoutedCompressionProvider.new,
    description: 'Gzip response compression for buffered responses.',
  );
}
