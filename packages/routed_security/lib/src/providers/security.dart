import 'package:routed_core/routed_core.dart';

import '../cors.dart';
import '../ip_filter.dart';

/// Immutable trusted-proxy settings.
class TrustedProxyConfig {
  TrustedProxyConfig({
    this.enabled = false,
    this.forwardClientIp = true,
    List<String>? proxies,
    List<String>? headers,
    this.platformHeader,
  }) : proxies = List<String>.unmodifiable(
         proxies ?? const ['0.0.0.0/0', '::/0'],
       ),
       headers = List<String>.unmodifiable(
         headers ?? const ['X-Forwarded-For', 'X-Real-IP'],
       );

  final bool enabled;
  final bool forwardClientIp;
  final List<String> proxies;
  final List<String> headers;
  final String? platformHeader;
}

/// Immutable IP allow/deny settings.
class IpFilterConfig {
  IpFilterConfig({
    this.enabled = false,
    this.defaultAction = IpFilterAction.allow,
    List<String>? allow,
    List<String>? deny,
    this.respectTrustedProxies = true,
  }) : allow = List<String>.unmodifiable(allow ?? const []),
       deny = List<String>.unmodifiable(deny ?? const []);

  final bool enabled;
  final IpFilterAction defaultAction;
  final List<String> allow;
  final List<String> deny;
  final bool respectTrustedProxies;
}

/// Immutable configuration for [RoutedSecurityProvider].
class RoutedSecurityConfig implements ValidatableConfiguration {
  RoutedSecurityConfig({
    this.maxRequestSize = 10 * 1024 * 1024,
    TrustedProxyConfig? trustedProxies,
    IpFilterConfig? ipFilter,
    this.cors = const CorsConfig(),
  }) : trustedProxies = trustedProxies ?? TrustedProxyConfig(),
       ipFilter = ipFilter ?? IpFilterConfig();

  final int maxRequestSize;
  final TrustedProxyConfig trustedProxies;
  final IpFilterConfig ipFilter;
  final CorsConfig cors;

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      maxRequestSize > 0,
      'maxRequestSize',
      'maximum request size must be greater than zero',
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

    context.require(
      cors.allowedOrigins.every((origin) => origin.trim().isNotEmpty),
      'cors.allowedOrigins',
      'allowed origins cannot contain empty values',
    );
    context.require(
      cors.allowedMethods.every((method) => method.trim().isNotEmpty),
      'cors.allowedMethods',
      'allowed methods cannot contain empty values',
    );
    context.require(
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

/// Registers CORS, trusted-proxy resolution, and optional IP filtering.
class RoutedSecurityProvider extends ServiceProvider
    with ProvidesTypedConfiguration<RoutedSecurityConfig> {
  RoutedSecurityProvider([RoutedSecurityConfig? configuration])
    : configuration = configuration ?? RoutedSecurityConfig();

  @override
  final RoutedSecurityConfig configuration;

  @override
  void register(Container container) {
    container.instance<TrustedProxyResolver>(
      _trustedProxyResolver(configuration.trustedProxies),
    );
  }

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
