/// Provider-registry integration for Routed security services.
library;

import 'package:routed_core/routed_core.dart' show ProviderRegistry;
import 'package:routed_security/src/providers/security.dart';

/// Registers the security provider factory in the shared registry.
///
/// The factory is registered under `routed.security` and creates a
/// [RoutedSecurityProvider]. Call this once before resolving the provider by
/// name from [ProviderRegistry]. Applications that construct providers
/// directly do not need to call this function.
void registerRoutedSecurityProviders() {
  ProviderRegistry.instance.register(
    'routed.security',
    factory: RoutedSecurityProvider.new,
    description: 'CORS, trusted proxies, and optional IP filtering.',
  );
}
