import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'providers/security.dart';

/// Registers the security provider factory in the shared registry.
void registerRoutedSecurityProviders() {
  ProviderRegistry.instance.register(
    'routed.security',
    factory: RoutedSecurityProvider.new,
    description: 'CORS, trusted proxies, and optional IP filtering.',
  );
}
