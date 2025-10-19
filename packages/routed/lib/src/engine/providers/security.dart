import 'dart:io';

import 'package:routed/middlewares.dart'
    show csrfMiddleware, requestSizeLimitMiddleware, securityHeadersMiddleware;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/security/ip_filter.dart';
import 'package:routed/src/security/network.dart';
import 'package:routed/src/security/trusted_proxy_resolver.dart';

/// Provides security middleware defaults (CSRF, headers, size limits).
class SecurityServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'routed.security': {
            'global': <String>[
              'routed.security.trusted_proxy',
              'routed.security.ip_filter',
              'routed.security.headers',
              'routed.security.csrf',
              'routed.security.request_size',
            ],
          },
        },
      },
    },
    docs: [
      ConfigDocEntry(
        path: 'security.max_request_size',
        type: 'int',
        description: 'Maximum request body size in bytes.',
        defaultValue: 10 * 1024 * 1024,
      ),
      ConfigDocEntry(
        path: 'security.headers',
        type: 'map<string,string>',
        description: 'Extra security headers applied to every response.',
        defaultValue: <String, String>{},
      ),
      ConfigDocEntry(
        path: 'security.csrf.enabled',
        type: 'bool',
        description: 'Enable CSRF middleware.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'security.csrf.cookie_name',
        type: 'string',
        description: 'Cookie used to store the CSRF token.',
        defaultValue: 'csrf_token',
      ),
      ConfigDocEntry(
        path: 'security.trusted_proxies.enabled',
        type: 'bool',
        description: 'Trust proxy headers for client IP resolution.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'security.trusted_proxies.proxies',
        type: 'list<string>',
        description: 'CIDR ranges considered trusted proxies.',
        defaultValue: ['0.0.0.0/0', '::/0'],
      ),
      ConfigDocEntry(
        path: 'security.trusted_proxies.headers',
        type: 'list<string>',
        description: 'Headers to inspect for client IP addresses.',
        defaultValue: ['X-Forwarded-For', 'X-Real-IP'],
      ),
      ConfigDocEntry(
        path: 'security.trusted_proxies.forward_client_ip',
        type: 'bool',
        description: 'Preserve the client IP from the first trusted header.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'security.trusted_proxies.platform_header',
        type: 'string',
        description:
            'Trusted platform header providing the original client IP (Cloudflare, AWS, etc.).',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'security.ip_filter.enabled',
        type: 'bool',
        description: 'Enable IP allow/deny middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'security.ip_filter.default_action',
        type: 'string',
        description: 'Fallback when no rules match (allow or deny).',
        options: ['allow', 'deny'],
        defaultValue: 'allow',
      ),
      ConfigDocEntry(
        path: 'security.ip_filter.allow',
        type: 'list<string>',
        description: 'CIDR/IP entries explicitly allowed.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'security.ip_filter.deny',
        type: 'list<string>',
        description: 'CIDR/IP entries explicitly denied.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'security.ip_filter.respect_trusted_proxies',
        type: 'bool',
        description: 'Use trusted proxy resolution when determining client IP.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'http.features.security.enabled',
        type: 'bool',
        description:
            'Feature toggle for core security middleware (headers, CSRF, size limits).',
        defaultValue: true,
      ),
    ],
  );

  IpFilter _ipFilter = IpFilter.disabled();

  @override
  void register(Container container) {
    final config = container.get<Config>();
    final trustedResolver = _buildTrustedProxyResolver(container, config);
    container.instance<TrustedProxyResolver>(trustedResolver);
    _ipFilter = _buildIpFilter(config);

    final registry = container.get<MiddlewareRegistry>();
    registry
      ..register(
        'routed.security.trusted_proxy',
        (c) => _trustedProxyMiddleware(c.get<TrustedProxyResolver>()),
      )
      ..register('routed.security.ip_filter', (_) => _ipFilterMiddleware())
      ..register('routed.security.headers', (_) => securityHeadersMiddleware())
      ..register('routed.security.csrf', (_) => csrfMiddleware())
      ..register(
        'routed.security.request_size',
        (_) => requestSizeLimitMiddleware(),
      );
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final updated = _buildTrustedProxyResolver(container, config);
    container.instance<TrustedProxyResolver>(updated);
    _ipFilter = _buildIpFilter(config);
  }

  TrustedProxyResolver _buildTrustedProxyResolver(
    Container container,
    Config config,
  ) {
    _validateSecurityConfig(config);

    final trustedNode = config.get('security.trusted_proxies');
    if (trustedNode != null && trustedNode is! Map && trustedNode is! Config) {
      throw ProviderConfigException('security.trusted_proxies must be a map');
    }

    final engineConfig = container.get<EngineConfig>();

    final enabled =
        parseBoolLike(
          config.get('security.trusted_proxies.enabled'),
          context: 'security.trusted_proxies.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        engineConfig.features.enableProxySupport;

    final forward =
        parseBoolLike(
          config.get('security.trusted_proxies.forward_client_ip'),
          context: 'security.trusted_proxies.forward_client_ip',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        engineConfig.forwardedByClientIP;

    final proxies =
        parseStringList(
          config.get('security.trusted_proxies.proxies'),
          context: 'security.trusted_proxies.proxies',
          allowEmptyResult: true,
          coerceNonStringEntries: false,
        ) ??
        const [];
    final headers =
        parseStringList(
          config.get('security.trusted_proxies.headers'),
          context: 'security.trusted_proxies.headers',
          allowEmptyResult: true,
          coerceNonStringEntries: false,
        ) ??
        const [];
    final platform = parseStringLike(
      config.get('security.trusted_proxies.platform_header'),
      context: 'security.trusted_proxies.platform_header',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );

    return TrustedProxyResolver(
      enabled: enabled,
      forwardClientIp: forward,
      proxies: proxies,
      headers: headers,
      trustedPlatform: platform == null || platform.isEmpty ? null : platform,
    );
  }

  Middleware _trustedProxyMiddleware(TrustedProxyResolver resolver) {
    return (ctx, next) async {
      final ip = resolver.resolve(ctx.request.httpRequest);
      ctx.request.overrideClientIp(ip);
      return next();
    };
  }

  Middleware _ipFilterMiddleware() {
    return (ctx, next) async {
      final filter = _ipFilter;
      if (!filter.enabled) {
        return next();
      }

      final ip = filter.respectTrustedProxies
          ? ctx.request.clientIP
          : ctx.request.remoteAddr;
      final candidate = ip.isEmpty ? ctx.request.remoteAddr : ip;

      if (!filter.allows(candidate)) {
        ctx.response.statusCode = HttpStatus.forbidden;
        if (!ctx.response.isClosed) {
          ctx.response.write('Forbidden');
        }
        return ctx.response;
      }

      return next();
    };
  }

  IpFilter _buildIpFilter(Config config) {
    final node = config.get('security.ip_filter');
    if (node == null) {
      return IpFilter.disabled();
    }

    final enabled =
        parseBoolLike(
          config.get('security.ip_filter.enabled'),
          context: 'security.ip_filter.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        false;
    if (!enabled) {
      return IpFilter.disabled();
    }

    final actionRaw = parseStringLike(
      config.get('security.ip_filter.default_action'),
      context: 'security.ip_filter.default_action',
      allowEmpty: false,
      throwOnInvalid: false,
    )?.toLowerCase();
    final defaultAction = actionRaw == 'deny'
        ? IpFilterAction.deny
        : IpFilterAction.allow;
    if (actionRaw != null && actionRaw != 'allow' && actionRaw != 'deny') {
      throw ProviderConfigException(
        'security.ip_filter.default_action must be "allow" or "deny"',
      );
    }

    final allowEntries =
        parseStringList(
          config.get('security.ip_filter.allow'),
          context: 'security.ip_filter.allow',
          allowEmptyResult: true,
          coerceNonStringEntries: false,
        ) ??
        const <String>[];

    final denyEntries =
        parseStringList(
          config.get('security.ip_filter.deny'),
          context: 'security.ip_filter.deny',
          allowEmptyResult: true,
          coerceNonStringEntries: false,
        ) ??
        const <String>[];

    final respectProxies =
        parseBoolLike(
          config.get('security.ip_filter.respect_trusted_proxies'),
          context: 'security.ip_filter.respect_trusted_proxies',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        true;

    List<NetworkMatcher> parseNetworks(List<String> entries, String context) {
      final result = <NetworkMatcher>[];
      for (final entry in entries) {
        try {
          result.add(NetworkMatcher.parse(entry));
        } on FormatException {
          throw ProviderConfigException(
            '$context contains invalid CIDR/IP "$entry"',
          );
        }
      }
      return result;
    }

    final allowMatchers = parseNetworks(
      allowEntries,
      'security.ip_filter.allow',
    );
    final denyMatchers = parseNetworks(denyEntries, 'security.ip_filter.deny');

    return IpFilter(
      enabled: true,
      defaultAction: defaultAction,
      allow: allowMatchers,
      deny: denyMatchers,
      respectTrustedProxies: respectProxies,
    );
  }

  void _validateSecurityConfig(Config config) {
    final securityNode = config.get('security');
    if (securityNode == null) {
      return;
    }
    if (securityNode is! Map) {
      throw ProviderConfigException('security must be a map');
    }

    final maxRequestSize = config.get('security.max_request_size');
    if (maxRequestSize != null) {
      final parsed = parseIntLike(
        maxRequestSize,
        context: 'security.max_request_size',
        nonNegative: true,
      );
      config.set('security.max_request_size', parsed);
    }

    final headersNode = config.get('security.headers');
    if (headersNode != null) {
      final sanitized = parseStringMap(
        headersNode as Object,
        context: 'security.headers',
      );
      config.set('security.headers', sanitized);
    }

    final csrfNode = config.get('security.csrf');
    if (csrfNode == null) {
      return;
    }
    if (csrfNode is! Map) {
      throw ProviderConfigException('security.csrf must be a map');
    }

    final enabledNode = config.get('security.csrf.enabled');
    if (enabledNode != null) {
      final enabled = parseBoolLike(
        enabledNode,
        context: 'security.csrf.enabled',
        stringMappings: const {'true': true, 'false': false},
      );
      config.set('security.csrf.enabled', enabled ?? true);
    }

    final cookieNode = config.get('security.csrf.cookie_name');
    if (cookieNode != null) {
      final cookieName = parseStringLike(
        cookieNode,
        context: 'security.csrf.cookie_name',
      );
      config.set('security.csrf.cookie_name', cookieName);
    }
  }
}
