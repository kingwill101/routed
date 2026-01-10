import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/security/ip_filter.dart';
import 'package:routed/src/security/network.dart';

import '../spec.dart';

const int _defaultMaxRequestSize = 10 * 1024 * 1024;
const String _defaultCsrfCookieName = 'csrf_token';
const List<String> _defaultTrustedProxies = ['0.0.0.0/0', '::/0'];
const List<String> _defaultTrustedProxyHeaders = [
  'X-Forwarded-For',
  'X-Real-IP',
];

class SecurityConfigContext extends ConfigSpecContext {
  const SecurityConfigContext({required this.engineConfig, super.config});

  final EngineConfig engineConfig;
}

class SecurityCsrfConfig {
  const SecurityCsrfConfig({required this.enabled, required this.cookieName});

  factory SecurityCsrfConfig.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? defaults,
    String context = 'security.csrf',
  }) {
    final effectiveDefaults = defaults ?? const <String, dynamic>{};
    final defaultEnabled =
        parseBoolLike(
          effectiveDefaults['enabled'],
          context: '$context.enabled',
          throwOnInvalid: false,
        ) ??
        true;
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: '$context.enabled',
          throwOnInvalid: true,
        ) ??
        defaultEnabled;

    final defaultCookie =
        parseStringLike(
          effectiveDefaults['cookie_name'],
          context: '$context.cookie_name',
          allowEmpty: true,
          throwOnInvalid: false,
        ) ??
        _defaultCsrfCookieName;
    final cookieName =
        parseStringLike(
          map['cookie_name'],
          context: '$context.cookie_name',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        defaultCookie;

    return SecurityCsrfConfig(enabled: enabled, cookieName: cookieName);
  }

  final bool enabled;
  final String cookieName;
}

class SecurityTrustedProxyConfig {
  const SecurityTrustedProxyConfig({
    required this.enabled,
    required this.forwardClientIp,
    required this.proxies,
    required this.headers,
    required this.platformHeader,
  });

  factory SecurityTrustedProxyConfig.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? defaults,
    String context = 'security.trusted_proxies',
  }) {
    final effectiveDefaults = defaults ?? const <String, dynamic>{};
    final defaultEnabled =
        parseBoolLike(
          effectiveDefaults['enabled'],
          context: '$context.enabled',
          throwOnInvalid: false,
        ) ??
        false;
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: '$context.enabled',
          throwOnInvalid: true,
        ) ??
        defaultEnabled;

    final defaultForward =
        parseBoolLike(
          effectiveDefaults['forward_client_ip'],
          context: '$context.forward_client_ip',
          throwOnInvalid: false,
        ) ??
        true;
    final forwardClientIp =
        parseBoolLike(
          map['forward_client_ip'],
          context: '$context.forward_client_ip',
          throwOnInvalid: true,
        ) ??
        defaultForward;

    final defaultProxies =
        parseStringList(
          effectiveDefaults['proxies'],
          context: '$context.proxies',
          allowEmptyResult: true,
          throwOnInvalid: false,
        ) ??
        _defaultTrustedProxies;
    final proxies =
        parseStringList(
          map['proxies'],
          context: '$context.proxies',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        defaultProxies;

    final defaultHeaders =
        parseStringList(
          effectiveDefaults['headers'],
          context: '$context.headers',
          allowEmptyResult: true,
          throwOnInvalid: false,
        ) ??
        _defaultTrustedProxyHeaders;
    final headers =
        parseStringList(
          map['headers'],
          context: '$context.headers',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        defaultHeaders;

    var platformHeader =
        parseStringLike(
          map['platform_header'],
          context: '$context.platform_header',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        parseStringLike(
          effectiveDefaults['platform_header'],
          context: '$context.platform_header',
          allowEmpty: true,
          throwOnInvalid: false,
        );
    if (platformHeader != null && platformHeader.isEmpty) {
      platformHeader = null;
    }

    return SecurityTrustedProxyConfig(
      enabled: enabled,
      forwardClientIp: forwardClientIp,
      proxies: proxies,
      headers: headers,
      platformHeader: platformHeader,
    );
  }

  final bool enabled;
  final bool forwardClientIp;
  final List<String> proxies;
  final List<String> headers;
  final String? platformHeader;
}

class SecurityIpFilterConfig {
  const SecurityIpFilterConfig({
    required this.enabled,
    required this.defaultAction,
    required this.allow,
    required this.deny,
    required this.allowMatchers,
    required this.denyMatchers,
    required this.respectTrustedProxies,
  });

  factory SecurityIpFilterConfig.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? defaults,
    String context = 'security.ip_filter',
  }) {
    final effectiveDefaults = defaults ?? const <String, dynamic>{};
    final defaultEnabled =
        parseBoolLike(
          effectiveDefaults['enabled'],
          context: '$context.enabled',
          throwOnInvalid: false,
        ) ??
        false;
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: '$context.enabled',
          throwOnInvalid: true,
        ) ??
        defaultEnabled;

    final defaultAction =
        parseStringLike(
          effectiveDefaults['default_action'],
          context: '$context.default_action',
          allowEmpty: true,
          throwOnInvalid: false,
        ) ??
        'allow';
    final actionToken =
        parseStringLike(
          map['default_action'],
          context: '$context.default_action',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        defaultAction;
    final action = actionToken.toLowerCase();
    if (action != 'allow' && action != 'deny') {
      throw ProviderConfigException(
        '$context.default_action must be "allow" or "deny"',
      );
    }

    final defaultAllow =
        parseStringList(
          effectiveDefaults['allow'],
          context: '$context.allow',
          allowEmptyResult: true,
          throwOnInvalid: false,
        ) ??
        const <String>[];
    final allow =
        parseStringList(
          map['allow'],
          context: '$context.allow',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        defaultAllow;
    final defaultDeny =
        parseStringList(
          effectiveDefaults['deny'],
          context: '$context.deny',
          allowEmptyResult: true,
          throwOnInvalid: false,
        ) ??
        const <String>[];
    final deny =
        parseStringList(
          map['deny'],
          context: '$context.deny',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        defaultDeny;

    final allowMatchers = enabled
        ? _parseNetworkMatchers(allow, '$context.allow')
        : const <NetworkMatcher>[];
    final denyMatchers = enabled
        ? _parseNetworkMatchers(deny, '$context.deny')
        : const <NetworkMatcher>[];

    final defaultRespect =
        parseBoolLike(
          effectiveDefaults['respect_trusted_proxies'],
          context: '$context.respect_trusted_proxies',
          throwOnInvalid: false,
        ) ??
        true;
    final respectTrustedProxies =
        parseBoolLike(
          map['respect_trusted_proxies'],
          context: '$context.respect_trusted_proxies',
          throwOnInvalid: true,
        ) ??
        defaultRespect;

    return SecurityIpFilterConfig(
      enabled: enabled,
      defaultAction: action == 'deny'
          ? IpFilterAction.deny
          : IpFilterAction.allow,
      allow: allow,
      deny: deny,
      allowMatchers: allowMatchers,
      denyMatchers: denyMatchers,
      respectTrustedProxies: respectTrustedProxies,
    );
  }

  final bool enabled;
  final IpFilterAction defaultAction;
  final List<String> allow;
  final List<String> deny;
  final List<NetworkMatcher> allowMatchers;
  final List<NetworkMatcher> denyMatchers;
  final bool respectTrustedProxies;

  static List<NetworkMatcher> _parseNetworkMatchers(
    List<String> entries,
    String context,
  ) {
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
}

class SecurityProviderConfig {
  const SecurityProviderConfig({
    required this.maxRequestSize,
    required this.headers,
    required this.csrf,
    required this.trustedProxies,
    required this.ipFilter,
  });

  factory SecurityProviderConfig.fromMap(
    Map<String, dynamic> map, {
    required Map<String, dynamic> defaults,
  }) {
    final maxRequestDefault =
        defaults['max_request_size'] as int? ?? _defaultMaxRequestSize;
    final maxRequestSize =
        parseIntLike(
          map['max_request_size'],
          context: 'security.max_request_size',
          nonNegative: true,
          throwOnInvalid: true,
        ) ??
        maxRequestDefault;

    final headersDefaultRaw = defaults['headers'];
    final Map<String, String> headersDefault = headersDefaultRaw is Map
        ? parseStringMap(headersDefaultRaw, context: 'security.headers')
        : const <String, String>{};
    final headersRaw = map['headers'];
    final Map<String, String> headers;
    if (headersRaw == null) {
      headers = Map<String, String>.from(headersDefault);
    } else {
      headers = parseStringMap(
        headersRaw as Object,
        context: 'security.headers',
      );
    }

    final csrfDefault = (defaults['csrf'] as Map<String, dynamic>?) ?? const {};
    final csrfRaw = map['csrf'];
    final SecurityCsrfConfig csrf;
    if (csrfRaw == null) {
      csrf = SecurityCsrfConfig.fromMap(
        Map<String, dynamic>.from(csrfDefault),
        defaults: csrfDefault,
        context: 'security.csrf',
      );
    } else {
      csrf = SecurityCsrfConfig.fromMap(
        stringKeyedMap(csrfRaw as Object, 'security.csrf'),
        defaults: csrfDefault,
        context: 'security.csrf',
      );
    }

    final trustedDefault =
        (defaults['trusted_proxies'] as Map<String, dynamic>?) ?? const {};
    final trustedRaw = map['trusted_proxies'];
    final SecurityTrustedProxyConfig trustedProxies;
    if (trustedRaw == null) {
      trustedProxies = SecurityTrustedProxyConfig.fromMap(
        Map<String, dynamic>.from(trustedDefault),
        defaults: trustedDefault,
        context: 'security.trusted_proxies',
      );
    } else {
      trustedProxies = SecurityTrustedProxyConfig.fromMap(
        stringKeyedMap(trustedRaw as Object, 'security.trusted_proxies'),
        defaults: trustedDefault,
        context: 'security.trusted_proxies',
      );
    }

    final ipFilterDefault =
        (defaults['ip_filter'] as Map<String, dynamic>?) ?? const {};
    final ipFilterRaw = map['ip_filter'];
    final SecurityIpFilterConfig ipFilter;
    if (ipFilterRaw == null) {
      ipFilter = SecurityIpFilterConfig.fromMap(
        Map<String, dynamic>.from(ipFilterDefault),
        defaults: ipFilterDefault,
        context: 'security.ip_filter',
      );
    } else {
      ipFilter = SecurityIpFilterConfig.fromMap(
        stringKeyedMap(ipFilterRaw as Object, 'security.ip_filter'),
        defaults: ipFilterDefault,
        context: 'security.ip_filter',
      );
    }

    return SecurityProviderConfig(
      maxRequestSize: maxRequestSize,
      headers: headers,
      csrf: csrf,
      trustedProxies: trustedProxies,
      ipFilter: ipFilter,
    );
  }

  final int maxRequestSize;
  final Map<String, String> headers;
  final SecurityCsrfConfig csrf;
  final SecurityTrustedProxyConfig trustedProxies;
  final SecurityIpFilterConfig ipFilter;
}

class SecurityConfigSpec extends ConfigSpec<SecurityProviderConfig> {
  const SecurityConfigSpec();

  @override
  String get root => 'security';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Security Configuration',
    description: 'CSRF, trusted proxies, and IP filtering settings.',
    properties: {
      'max_request_size': ConfigSchema.integer(
        description: 'Maximum request body size in bytes.',
        defaultValue: _defaultMaxRequestSize,
      ),
      'headers': ConfigSchema.object(
        description: 'Extra security headers applied to every response.',
        additionalProperties: true,
      ).withDefault(const {}),
      'csrf': ConfigSchema.object(
        description: 'CSRF protection settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Enable CSRF middleware.',
            defaultValue: true,
          ),
          'cookie_name': ConfigSchema.string(
            description: 'Cookie used to store the CSRF token.',
            defaultValue: _defaultCsrfCookieName,
          ),
        },
      ),
      'trusted_proxies': ConfigSchema.object(
        description: 'Trusted proxy settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Trust proxy headers for client IP resolution.',
            defaultValue: false,
          ),
          'proxies': ConfigSchema.list(
            description: 'CIDR ranges considered trusted proxies.',
            items: ConfigSchema.string(),
            defaultValue: _defaultTrustedProxies,
          ),
          'headers': ConfigSchema.list(
            description: 'Headers to inspect for client IP addresses.',
            items: ConfigSchema.string(),
            defaultValue: _defaultTrustedProxyHeaders,
          ),
          'forward_client_ip': ConfigSchema.boolean(
            description:
                'Preserve the client IP from the first trusted header.',
            defaultValue: true,
          ),
          'platform_header': ConfigSchema.string(
            description:
                'Trusted platform header providing the original client IP (Cloudflare, AWS, etc.).',
          ),
        },
      ),
      'ip_filter': ConfigSchema.object(
        description: 'IP allow/deny settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Enable IP allow/deny middleware.',
            defaultValue: false,
          ),
          'default_action': ConfigSchema.string(
            description: 'Fallback when no rules match (allow or deny).',
            options: ['allow', 'deny'],
            defaultValue: 'allow',
          ),
          'allow': ConfigSchema.list(
            description: 'CIDR/IP entries explicitly allowed.',
            items: ConfigSchema.string(),
            defaultValue: const [],
          ),
          'deny': ConfigSchema.list(
            description: 'CIDR/IP entries explicitly denied.',
            items: ConfigSchema.string(),
            defaultValue: const [],
          ),
          'respect_trusted_proxies': ConfigSchema.boolean(
            description:
                'Use trusted proxy resolution when determining client IP.',
            defaultValue: true,
          ),
        },
      ),
    },
  );

  @override
  SecurityProviderConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final defaultsMap = defaults(context: context);
    return SecurityProviderConfig.fromMap(map, defaults: defaultsMap);
  }

  @override
  Map<String, dynamic> toMap(SecurityProviderConfig value) {
    return {
      'max_request_size': value.maxRequestSize,
      'headers': value.headers,
      'csrf': {
        'enabled': value.csrf.enabled,
        'cookie_name': value.csrf.cookieName,
      },
      'trusted_proxies': {
        'enabled': value.trustedProxies.enabled,
        'proxies': value.trustedProxies.proxies,
        'headers': value.trustedProxies.headers,
        'forward_client_ip': value.trustedProxies.forwardClientIp,
        'platform_header': value.trustedProxies.platformHeader,
      },
      'ip_filter': {
        'enabled': value.ipFilter.enabled,
        'default_action': value.ipFilter.defaultAction == IpFilterAction.deny
            ? 'deny'
            : 'allow',
        'allow': value.ipFilter.allow,
        'deny': value.ipFilter.deny,
        'respect_trusted_proxies': value.ipFilter.respectTrustedProxies,
      },
    };
  }
}
