library;

import 'src/register_providers.dart';

// Batteries-included Routed: core engine + official feature packages.
// Importing this library registers zero-arg feature providers for http.providers.
export 'package:routed_core/routed_core.dart'
    hide
        ProviderConfigException,
        ConfigSchema,
        CookieStore,
        stringKeyedMap,
        FilesystemStore,
        parseBoolLike,
        parseStringLike,
        parseStringList,
        parseStringMap,
        parseStringMapAllowNulls,
        parseMapList,
        parseIntLike,
        parseDoubleLike,
        parseDurationLike,
        SecureCookie,
        NamedRegistry,
        ViewEngine,
        LiquidViewEngine;
export 'package:server_auth/server_auth.dart' hide NamedRegistry;
export 'package:server_cache/server_cache.dart';
export 'package:server_sessions/server_sessions.dart';
export 'package:server_storage/server_storage.dart';
export 'package:server_rate_limit/server_rate_limit.dart';
export 'package:routed_auth/routed_auth.dart';
export 'package:routed_cache/routed_cache.dart';
export 'package:routed_sessions/routed_sessions.dart';
export 'package:routed_storage/routed_storage.dart';
export 'package:routed_rate_limit/routed_rate_limit.dart';
export 'package:routed_views/routed_views.dart';
export 'package:routed_http/routed_http.dart';
export 'package:routed_logging/routed_logging.dart';
export 'package:routed_observability/routed_observability.dart';
export 'src/register_providers.dart' show registerRoutedProviders;

final _ensureProviders = (() {
  registerRoutedProviders();
  return true;
})();

/// Whether official providers were registered via this barrel import.
bool get officialProvidersRegistered => _ensureProviders;
