/// The batteries-included facade for the Routed framework.
///
/// This library re-exports the core engine and official feature packages from
/// one import. Register the official provider factories before creating an
/// engine, then let [Engine.create] initialize the resulting composition.
///
/// ```dart
/// import 'package:routed/routed.dart';
///
/// Future<void> main() async {
///   registerRoutedProviders();
///   final engine = await Engine.create();
///   engine.get('/health', (ctx) => ctx.json({'ok': true}));
///   await engine.serve(port: 8080);
/// }
/// ```
///
/// [Engine.create] uses [Engine.builtins], which is populated from the shared
/// [ProviderRegistry]. The explicit registration call makes that startup
/// dependency visible and is safe to call more than once. For a smaller
/// application, pass only the providers it needs to [Engine.create] or use
/// `package:routed_core` directly.
library;

import 'package:routed/src/register_providers.dart';
import 'package:routed_core/routed_core.dart' show Engine, ProviderRegistry;

// Batteries-included Routed: core engine + official feature packages.
export 'package:routed_auth/routed_auth.dart';
export 'package:routed_cache/routed_cache.dart';
export 'package:routed_core/routed_core.dart' hide ProviderConfigException;
export 'package:routed_http/routed_http.dart';
export 'package:routed_logging/routed_logging.dart';
export 'package:routed_observability/routed_observability.dart';
export 'package:routed_openapi/routed_openapi.dart';
export 'package:routed_rate_limit/routed_rate_limit.dart';
export 'package:routed_security/routed_security.dart';
export 'package:routed_sessions/routed_sessions.dart';
export 'package:routed_storage/routed_storage.dart';
export 'package:routed_validation/routed_validation.dart';
export 'package:routed_views/routed_views.dart';
export 'src/register_providers.dart' show registerRoutedProviders;

final bool _ensureProviders = (() {
  registerRoutedProviders();
  return true;
})();

/// Ensures the official providers are registered and returns `true`.
///
/// Reading this getter performs the same initialization as
/// [registerRoutedProviders]. Normal application startup should call the
/// registration function explicitly so the order is clear; this getter is
/// useful for a small initialization check or an assertion.
bool get officialProvidersRegistered => _ensureProviders;
