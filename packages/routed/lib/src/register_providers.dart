import 'package:routed_auth/routed_auth.dart';
import 'package:routed_logging/routed_logging.dart';
import 'package:routed_cache/routed_cache.dart';
import 'package:routed_observability/routed_observability.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:routed_security/routed_security.dart';
import 'package:routed_http/routed_http.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:routed_views/routed_views.dart';

/// Registers all official feature providers for `http.providers` resolution.
///
/// Providers that need custom runtime deps can still be passed explicitly:
/// `Engine(providers: [RoutedCacheProvider(customStore), ...])`.
void registerRoutedProviders() {
  registerRoutedAuthProviders();
  registerRoutedLoggingProviders();
  registerRoutedViewsProviders();
  registerRoutedObservabilityProviders();
  registerRoutedCacheProviders();
  registerRoutedSessionsProviders();
  registerRoutedStorageProviders();
  registerRoutedRateLimitProviders();
  registerRoutedHttpProviders();
  registerRoutedSecurityProviders();
}
