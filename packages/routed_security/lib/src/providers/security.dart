import 'dart:io';

import 'package:routed_core/routed_core.dart';

import '../cors.dart';
import '../ip_filter.dart';

/// Registers CORS, trusted-proxy resolution, and optional IP filtering.
class RoutedSecurityProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  Middleware? _ipFilterMiddleware;
  Middleware? _corsMiddleware;

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    values: {
      'security': {
        'max_request_size': 10 * 1024 * 1024,
        'trusted_proxies': {
          'enabled': false,
          'proxies': ['0.0.0.0/0', '::/0'],
          'headers': ['X-Forwarded-For', 'X-Real-IP'],
          'forward_client_ip': true,
          'platform_header': null,
        },
        'ip_filter': {
          'enabled': false,
          'default_action': 'allow',
          'allow': <String>[],
          'deny': <String>[],
          'respect_trusted_proxies': true,
        },
      },
      'cors': {
        'enabled': false,
        'allowed_origins': ['*'],
        'allowed_methods': ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
        'allowed_headers': <String>[],
        'allow_credentials': false,
        'max_age': null,
        'exposed_headers': <String>[],
      },
    },
    docs: const [
      ConfigDocEntry(
        path: 'security.max_request_size',
        type: 'int',
        description: 'Maximum request body size in bytes.',
        defaultValue: 10 * 1024 * 1024,
      ),
      ConfigDocEntry(
        path: 'security.trusted_proxies',
        type: 'map',
        description: 'Trusted proxy and forwarded-client-IP settings.',
      ),
      ConfigDocEntry(
        path: 'security.ip_filter',
        type: 'map',
        description: 'Optional IP allow and deny rules.',
      ),
      ConfigDocEntry(
        path: 'cors',
        type: 'map',
        description: 'Cross-origin request and preflight policy.',
      ),
    ],
  );

  @override
  void register(Container container) {
    final config = container.get<Config>();
    container.instance<TrustedProxyResolver>(_trustedProxyResolver(config));

    final middlewareRegistry = container.get<MiddlewareRegistry>();
    middlewareRegistry.register(
      'routed.security.ip_filter',
      (_) => _ipFilterMiddlewareFor(config),
    );
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Engine>() || !container.has<Config>()) return;
    _apply(container.get<Engine>(), container.get<Config>());
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    if (!container.has<Engine>()) return;
    _apply(container.get<Engine>(), config);
  }

  void _apply(Engine engine, Config config) {
    final trusted = _trustedProxySettings(config);
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

    engine.updateConfig(
      current.copyWith(
        features: features,
        forwardedByClientIP: trusted.forwardClientIp,
        remoteIPHeaders: trusted.headers,
        trustedProxies: trusted.proxies,
        trustedPlatform: trusted.platformHeader,
      ),
    );

    final filter = _ipFilterSettings(config);
    final existingCors = _corsMiddleware;
    if (existingCors != null) {
      engine.middlewares.removeWhere(
        (middleware) => identical(middleware, existingCors),
      );
      _corsMiddleware = null;
    }
    final cors = current.security.cors;
    if (cors.enabled) {
      final middleware = corsMiddleware(cors);
      _corsMiddleware = middleware;
      engine.middlewares.insert(0, middleware);
    }

    final existing = _ipFilterMiddleware;
    if (existing != null) {
      engine.middlewares.removeWhere(
        (middleware) => identical(middleware, existing),
      );
      _ipFilterMiddleware = null;
    }

    if (filter.enabled) {
      final middleware = _ipFilterMiddlewareFor(config);
      _ipFilterMiddleware = middleware;
      engine.middlewares.insert(0, middleware);
      engine.updateConfig(engine.config);
    }

    engine.container.instance<TrustedProxyResolver>(
      _trustedProxyResolver(config),
    );
  }

  Middleware _ipFilterMiddlewareFor(Config config) {
    final filter = _ipFilterSettings(config);
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

  TrustedProxyResolver _trustedProxyResolver(Config config) {
    final trusted = _trustedProxySettings(config);
    return TrustedProxyResolver(
      enabled: trusted.enabled,
      forwardClientIp: trusted.forwardClientIp,
      proxies: trusted.proxies,
      headers: trusted.headers,
      trustedPlatform: trusted.platformHeader,
    );
  }

  _TrustedProxySettings _trustedProxySettings(Config config) {
    return _TrustedProxySettings(
      enabled: _bool(config, 'security.trusted_proxies.enabled', false),
      forwardClientIp: _bool(
        config,
        'security.trusted_proxies.forward_client_ip',
        true,
      ),
      proxies: _strings(config, 'security.trusted_proxies.proxies', const [
        '0.0.0.0/0',
        '::/0',
      ]),
      headers: _strings(config, 'security.trusted_proxies.headers', const [
        'X-Forwarded-For',
        'X-Real-IP',
      ]),
      platformHeader: _stringOrNull(
        config,
        'security.trusted_proxies.platform_header',
      ),
    );
  }

  _IpFilterSettings _ipFilterSettings(Config config) {
    final allow = _strings(config, 'security.ip_filter.allow', const []);
    final deny = _strings(config, 'security.ip_filter.deny', const []);
    return _IpFilterSettings(
      enabled: _bool(config, 'security.ip_filter.enabled', false),
      defaultAction:
          _string(
                config,
                'security.ip_filter.default_action',
                'allow',
              ).toLowerCase() ==
              'deny'
          ? IpFilterAction.deny
          : IpFilterAction.allow,
      allow: allow
          .map(NetworkMatcher.maybeParse)
          .whereType<NetworkMatcher>()
          .toList(),
      deny: deny
          .map(NetworkMatcher.maybeParse)
          .whereType<NetworkMatcher>()
          .toList(),
      respectTrustedProxies: _bool(
        config,
        'security.ip_filter.respect_trusted_proxies',
        true,
      ),
    );
  }

  static bool _bool(Config config, String key, bool fallback) {
    final value = config.get<Object?>(key);
    if (value is bool) return value;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case '1':
        case 'true':
        case 'yes':
        case 'on':
          return true;
        case '0':
        case 'false':
        case 'no':
        case 'off':
          return false;
      }
    }
    return fallback;
  }

  static String _string(Config config, String key, String fallback) {
    final value = config.get<Object?>(key);
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static String? _stringOrNull(Config config, String key) {
    final value = config.get<Object?>(key);
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static List<String> _strings(
    Config config,
    String key,
    List<String> fallback,
  ) {
    final value = config.get<Object?>(key);
    if (value is Iterable) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return List<String>.from(fallback);
  }
}

class _TrustedProxySettings {
  const _TrustedProxySettings({
    required this.enabled,
    required this.forwardClientIp,
    required this.proxies,
    required this.headers,
    required this.platformHeader,
  });

  final bool enabled;
  final bool forwardClientIp;
  final List<String> proxies;
  final List<String> headers;
  final String? platformHeader;
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
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null) return defaultAction == IpFilterAction.allow;
    for (final matcher in deny) {
      if (matcher.contains(parsed)) return false;
    }
    for (final matcher in allow) {
      if (matcher.contains(parsed)) return true;
    }
    return defaultAction == IpFilterAction.allow;
  }
}
