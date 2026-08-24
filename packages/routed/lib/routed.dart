/// The batteries-included facade for the Routed framework.
///
/// This library re-exports the core engine and official feature packages and
/// registers their built-in providers when it is first loaded. Call
/// [registerRoutedProviders] explicitly when startup order needs to be
/// visible in application code.
library;

import 'package:routed/src/register_providers.dart';

// Batteries-included Routed: core engine + official feature packages.
// Call registerRoutedProviders() before using Engine.builtins or
// Engine.create() when the full official provider catalogue is required.
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

/// Whether official providers have been registered through this barrel.
bool get officialProvidersRegistered => _ensureProviders;
