/// Security middleware, typed configuration, and provider integrations for
/// Routed applications.
///
/// The package provides [RoutedSecurityProvider] for applying request-size,
/// CORS, trusted-proxy, and IP filtering settings during engine startup. The
/// lower-level [corsMiddleware] and [IpFilter] APIs can also be composed
/// directly when an application needs a narrower integration.
///
/// ```dart
/// import 'package:routed_core/routed_core.dart';
/// import 'package:routed_security/routed_security.dart';
///
/// final security = RoutedSecurityProvider(
///   RoutedSecurityConfig(
///     cors: const CorsConfig(
///       enabled: true,
///       allowedOrigins: ['https://app.example'],
///     ),
///   ),
/// );
/// ```
library;

import 'package:routed_security/src/cors.dart';
import 'package:routed_security/src/ip_filter.dart';
import 'package:routed_security/src/providers/security.dart';

export 'src/cors.dart';
export 'src/ip_filter.dart';
export 'src/network.dart';
export 'src/providers/security.dart';
export 'src/register_providers.dart';
export 'src/trusted_proxy_resolver.dart';
