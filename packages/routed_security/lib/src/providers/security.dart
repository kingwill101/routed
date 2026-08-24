/// Typed security configuration and the provider that applies it to an
/// engine.
library;

import 'package:routed_core/routed_core.dart';
import 'package:routed_security/src/cors.dart';
import 'package:routed_security/src/ip_filter.dart';

/// Immutable settings for resolving client addresses through trusted proxies.
class TrustedProxyConfig {
  /// Creates trusted-proxy settings.
  ///
  /// [proxies] contains trusted IP addresses or CIDR ranges. [headers]
  /// contains the forwarded-address headers accepted from those proxies. The
  /// default headers are `X-Forwarded-For` and `X-Real-IP`.
  ///
  /// When [enabled] is `true`, [RoutedSecurityConfig.validate] requires at
  /// least one explicit proxy network before the provider can boot.
  TrustedProxyConfig({
    this.enabled = false,
    this.forwardClientIp = true,
    List<String>? proxies,
    List<String>? headers,
    this.platformHeader,
  }) : proxies = List<String>.unmodifiable(proxies ?? const []),
       headers = List<String>.unmodifiable(
         headers ?? const ['X-Forwarded-For', 'X-Real-IP'],
       );

  /// Whether forwarded client information from [proxies] is trusted.
  final bool enabled;

  /// Whether request helpers should use the resolved forwarded client address.
  final bool forwardClientIp;

  /// Trusted proxy IP addresses or CIDR ranges.
  final List<String> proxies;

  /// Header names inspected for a forwarded client address.
  final List<String> headers;

  /// Optional platform-specific header accepted from a trusted platform.
  final String? platformHeader;
}

/// Immutable settings for IP-based allow and deny filtering.
class IpFilterConfig {
  /// Creates IP allow/deny settings.
  ///
  /// [allow] and [deny] contain IP addresses or CIDR ranges. Deny rules take
  /// precedence over allow rules when both match an address. Filtering is
  /// disabled by default and unmatched addresses are allowed by default.
  IpFilterConfig({
    this.enabled = false,
    this.defaultAction = IpFilterAction.allow,
    List<String>? allow,
    List<String>? deny,
    this.respectTrustedProxies = true,
  }) : allow = List<String>.unmodifiable(allow ?? const []),
       deny = List<String>.unmodifiable(deny ?? const []);

  /// Whether IP filtering is active.
  final bool enabled;

  /// Action to take when no allow or deny rule matches an address.
  final IpFilterAction defaultAction;

  /// IP addresses or CIDR ranges that are allowed when filtering is enabled.
  final List<String> allow;

  /// IP addresses or CIDR ranges that are denied when filtering is enabled.
  final List<String> deny;

  /// Whether filtering uses the trusted-proxy-aware client address instead of
  /// the direct peer address.
  final bool respectTrustedProxies;
}

/// Immutable configuration for [RoutedSecurityProvider].
class RoutedSecurityConfig implements ValidatableConfiguration {
  /// Creates configuration for CORS, proxy resolution, and IP filtering.
  ///
  /// [maxRequestSize] is measured in bytes and defaults to 10 MiB. If omitted,
  /// [trustedProxies] and [ipFilter] use their disabled defaults, while
  /// [cors] uses [CorsConfig]'s defaults.
  RoutedSecurityConfig({
    this.maxRequestSize = 10 * 1024 * 1024,
    TrustedProxyConfig? trustedProxies,
    IpFilterConfig? ipFilter,
    this.cors = const CorsConfig(),
  }) : trustedProxies = trustedProxies ?? TrustedProxyConfig(),
       ipFilter = ipFilter ?? IpFilterConfig();

  /// Maximum request body size in bytes.
  final int maxRequestSize;

  /// Trusted-proxy address resolution settings.
  final TrustedProxyConfig trustedProxies;

  /// IP allow/deny settings.
  final IpFilterConfig ipFilter;

  /// CORS response-header and preflight settings.
  final CorsConfig cors;

  /// Adds configuration issues for invalid request sizes, networks, headers,
  /// and CORS settings to [context].
  ///
  /// Trusted-proxy support must include at least one explicit proxy network;
  /// this prevents forwarded client addresses from being trusted by accident.
  @override
  void validate(ConfigValidationContext context) {
    context
      ..require(
        maxRequestSize > 0,
        'maxRequestSize',
        'maximum request size must be greater than zero',
      )
      ..require(
        !trustedProxies.enabled || trustedProxies.proxies.isNotEmpty,
        'trustedProxies.proxies',
        'must contain at least one network when trusted proxy support '
            'is enabled',
      );
    _validateNetworkList(
      context,
      'trustedProxies.proxies',
      trustedProxies.proxies,
    );
    _validateHeaderList(
      context,
      'trustedProxies.headers',
      trustedProxies.headers,
    );
    _validateNetworkList(context, 'ipFilter.allow', ipFilter.allow);
    _validateNetworkList(context, 'ipFilter.deny', ipFilter.deny);

    context
      ..require(
        cors.allowedOrigins.every((origin) => origin.trim().isNotEmpty),
        'cors.allowedOrigins',
        'allowed origins cannot contain empty values',
      )
      ..require(
        cors.allowedMethods.every((method) => method.trim().isNotEmpty),
        'cors.allowedMethods',
        'allowed methods cannot contain empty values',
      )
      ..require(
        cors.maxAge == null || cors.maxAge! >= 0,
        'cors.maxAge',
        'maximum age cannot be negative',
      );
  }

  void _validateNetworkList(
    ConfigValidationContext context,
    String path,
    Iterable<String> values,
  ) {
    for (var index = 0; index < values.length; index++) {
      final value = values.elementAt(index);
      context.require(
        NetworkMatcher.maybeParse(value) != null,
        '$path[$index]',
        'must be a valid IP address or CIDR range',
      );
    }
  }

  void _validateHeaderList(
    ConfigValidationContext context,
    String path,
    Iterable<String> values,
  ) {
    for (var index = 0; index < values.length; index++) {
      context.require(
        values.elementAt(index).trim().isNotEmpty,
        '$path[$index]',
        'header names cannot be empty',
      );
    }
  }
}

/// Applies typed security settings to a Routed engine during its lifecycle.
///
/// Register this provider in the engine's provider list. During registration it
/// exposes a [TrustedProxyResolver]; during boot it applies request-size, CORS,
/// proxy, and optional IP-filter middleware settings to the available [Engine].
///
/// ```dart
/// final provider = RoutedSecurityProvider(
///   RoutedSecurityConfig(
///     ipFilter: IpFilterConfig(
///       enabled: true,
///       defaultAction: IpFilterAction.deny,
///       allow: ['10.0.0.0/8'],
///     ),
///   ),
/// );
/// ```
class RoutedSecurityProvider extends ServiceProvider
    with ProvidesTypedConfiguration<RoutedSecurityConfig> {
  /// Creates a provider using [configuration], or safe disabled defaults.
  ///
  /// Configuration is validated by Routed's typed provider lifecycle before
  /// the provider boots.
  RoutedSecurityProvider([RoutedSecurityConfig? configuration])
    : configuration = configuration ?? RoutedSecurityConfig();

  /// The typed settings applied by this provider.
  @override
  final RoutedSecurityConfig configuration;

  /// Registers the trusted-proxy resolver in [container].
  @override
  void register(Container container) {
    container.instance<TrustedProxyResolver>(
      _trustedProxyResolver(configuration.trustedProxies),
    );
  }

  /// Applies the configured security settings when an [Engine] is available.
  ///
  /// The provider does nothing when the container does not contain an engine,
  /// which allows the resolver binding to be used in smaller compositions.
  @override
  Future<void> boot(Container container) async {
    if (!container.has<Engine>()) return;
    _apply(container);
  }

  void _apply(Container container) {
    final engine = container.get<Engine>();
    final trusted = configuration.trustedProxies;
    final current = engine.config;
    final currentFeatures = current.features;
    final features = EngineFeatures(
      enableTrustedPlatform: trusted.enabled && trusted.platformHeader != null,
      enableProxySupport: trusted.enabled,
      enableSecurityFeatures: currentFeatures.enableSecurityFeatures,
      enableRequestZones: currentFeatures.enableRequestZones,
      enableRequestContainerFastPath:
          currentFeatures.enableRequestContainerFastPath,
      enableTrieRouting: currentFeatures.enableTrieRouting,
      enableSecureRequestIds: currentFeatures.enableSecureRequestIds,
    );

    final security = current.security.copyWith(
      maxRequestSize: configuration.maxRequestSize,
      cors: configuration.cors,
    );
    engine.updateConfig(
      current.copyWith(
        features: features,
        security: security,
        forwardedByClientIP: trusted.forwardClientIp,
        remoteIPHeaders: trusted.headers,
        trustedProxies: trusted.proxies,
        trustedPlatform: trusted.platformHeader,
      ),
    );

    if (configuration.cors.enabled) {
      engine.middlewares.insert(0, corsMiddleware(configuration.cors));
    }

    final filter = _ipFilterSettings(configuration.ipFilter);

    if (filter.enabled) {
      engine.middlewares.insert(0, _ipFilterMiddlewareFor(filter));
    }

    engine.container.instance<TrustedProxyResolver>(
      _trustedProxyResolver(trusted),
    );
  }

  Middleware _ipFilterMiddlewareFor(_IpFilterSettings filter) {
    return (ctx, next) {
      if (!filter.enabled) return next();

      final ip = filter.respectTrustedProxies
          ? ctx.request.clientIP
          : ctx.request.remoteAddr;
      if (filter.allows(ip)) return next();

      ctx.abortWithStatus(HttpStatus.forbidden, 'Forbidden');
      return ctx.response;
    };
  }

  _IpFilterSettings _ipFilterSettings(IpFilterConfig config) {
    return _IpFilterSettings(
      enabled: config.enabled,
      defaultAction: config.defaultAction,
      allow: config.allow.map(NetworkMatcher.parse).toList(growable: false),
      deny: config.deny.map(NetworkMatcher.parse).toList(growable: false),
      respectTrustedProxies: config.respectTrustedProxies,
    );
  }
}

TrustedProxyResolver _trustedProxyResolver(TrustedProxyConfig trusted) {
  return TrustedProxyResolver(
    enabled: trusted.enabled,
    forwardClientIp: trusted.forwardClientIp,
    proxies: trusted.proxies,
    headers: trusted.headers,
    trustedPlatform: trusted.platformHeader,
  );
}

class _IpFilterSettings {
  const _IpFilterSettings({
    required this.enabled,
    required this.defaultAction,
    required this.allow,
    required this.deny,
    required this.respectTrustedProxies,
  });

  final bool enabled;
  final IpFilterAction defaultAction;
  final List<NetworkMatcher> allow;
  final List<NetworkMatcher> deny;
  final bool respectTrustedProxies;

  bool allows(String ip) {
    if (!enabled) return true;
    for (final matcher in deny) {
      if (matcher.containsText(ip)) return false;
    }
    for (final matcher in allow) {
      if (matcher.containsText(ip)) return true;
    }
    return defaultAction == IpFilterAction.allow;
  }
}
