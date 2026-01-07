import 'dart:io';

import 'package:routed/middlewares.dart'
    show csrfMiddleware, requestSizeLimitMiddleware, securityHeadersMiddleware;
import 'package:routed/src/config/specs/security.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/security/ip_filter.dart';
import 'package:routed/src/security/trusted_proxy_resolver.dart';

/// Provides security middleware defaults (CSRF, headers, size limits).
class SecurityServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  static const SecurityConfigSpec spec = SecurityConfigSpec();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.security': {
          'global': [
            'routed.security.trusted_proxy',
            'routed.security.ip_filter',
            'routed.security.headers',
            'routed.security.csrf',
            'routed.security.request_size',
          ],
        },
      },
    };
    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'Security middleware references injected globally.',
          defaultValue: <String, Object?>{
            'routed.security': <String, Object?>{
              'global': <String>[
                'routed.security.trusted_proxy',
                'routed.security.ip_filter',
                'routed.security.headers',
                'routed.security.csrf',
                'routed.security.request_size',
              ],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
    );
  }

  IpFilter _ipFilter = IpFilter.disabled();

  @override
  void register(Container container) {
    final config = container.get<Config>();
    final engineConfig = container.get<EngineConfig>();
    final resolved = spec.resolve(
      config,
      context: SecurityConfigContext(
        config: config,
        engineConfig: engineConfig,
      ),
    );
    final trustedResolver = _buildTrustedProxyResolver(resolved);
    container.instance<TrustedProxyResolver>(trustedResolver);
    _ipFilter = _buildIpFilter(resolved);

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
    final engineConfig = container.get<EngineConfig>();
    final resolved = spec.resolve(
      config,
      context: SecurityConfigContext(
        config: config,
        engineConfig: engineConfig,
      ),
    );
    final updated = _buildTrustedProxyResolver(resolved);
    container.instance<TrustedProxyResolver>(updated);
    _ipFilter = _buildIpFilter(resolved);
  }

  TrustedProxyResolver _buildTrustedProxyResolver(
    SecurityProviderConfig config,
  ) {
    final trusted = config.trustedProxies;
    final platform = trusted.platformHeader;
    return TrustedProxyResolver(
      enabled: trusted.enabled,
      forwardClientIp: trusted.forwardClientIp,
      proxies: trusted.proxies,
      headers: trusted.headers,
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

  IpFilter _buildIpFilter(SecurityProviderConfig config) {
    final ipFilter = config.ipFilter;
    if (!ipFilter.enabled) {
      return IpFilter.disabled();
    }

    return IpFilter(
      enabled: true,
      defaultAction: ipFilter.defaultAction,
      allow: ipFilter.allowMatchers,
      deny: ipFilter.denyMatchers,
      respectTrustedProxies: ipFilter.respectTrustedProxies,
    );
  }
}
