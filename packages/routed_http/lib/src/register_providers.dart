import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'package:routed_http/src/providers/compression.dart';

/// Registers HTTP-related providers for direct `routed_http` users.
void registerRoutedHttpProviders() {
  ProviderRegistry.instance.register(
    'routed.compression',
    factory: RoutedCompressionProvider.new,
    description: 'Gzip response compression for buffered responses.',
  );
}
