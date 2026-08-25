import 'package:routed_auth/routed_auth.dart';
import 'package:routed_cache/routed_cache.dart';
import 'package:routed_core/routed_core.dart' show Engine;
import 'package:routed_http/routed_http.dart';
import 'package:routed_logging/routed_logging.dart';
import 'package:routed_observability/routed_observability.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:routed_security/routed_security.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_storage/routed_storage.dart';
import 'package:routed_views/routed_views.dart';

/// Registers all official feature provider factories in the shared registry.
///
/// Calling this function repeatedly is safe: existing registrations are kept.
/// After registration, [Engine.create] can discover the official providers
/// through [Engine.builtins].
///
/// Providers that need custom runtime dependencies should be composed
/// explicitly instead of being registered globally. For example, this creates
/// a core engine with a cache provider using a specific store:
///
/// ```dart
/// final engine = await Engine.create(
///   providers: [
///     ...Engine.defaultProviders,
///     RoutedCacheProvider(CacheConfig(store: ArrayStore())),
///   ],
/// );
/// ```
///
/// Supplying [Engine.create] with a `providers` list selects that list instead
/// of [Engine.builtins], so include every provider the application needs.
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
