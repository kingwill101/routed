import 'package:routed_auth/routed_auth.dart';
import 'package:routed_observability/routed_observability.dart';
import 'package:routed_views/routed_views.dart';

/// Registers official zero-arg feature providers for `http.providers`.
///
/// Providers that require runtime dependencies (cache store, session store,
/// storage manager, rate-limit service) must still be passed to
/// `Engine(providers: [...])` explicitly.
void registerRoutedFullProviders() {
  registerRoutedAuthProviders();
  registerRoutedViewsProviders();
  registerRoutedObservabilityProviders();
}
