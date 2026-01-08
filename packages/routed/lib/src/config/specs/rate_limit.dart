import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/rate_limit/policy.dart';

import '../spec.dart';

const int _defaultCapacity = 100;
const Duration _defaultInterval = Duration(minutes: 1);
const Duration _defaultWindow = Duration(minutes: 1);
const Duration _defaultPeriod = Duration(hours: 24);

enum RateLimitKeyType { ip, header }

class RateLimitKeyConfig {
  const RateLimitKeyConfig.ip() : type = RateLimitKeyType.ip, header = null;

  const RateLimitKeyConfig.header(this.header) : type = RateLimitKeyType.header;

  factory RateLimitKeyConfig.fromMap(Object? raw, {required String context}) {
    if (raw == null) {
      return const RateLimitKeyConfig.ip();
    }
    final map = stringKeyedMap(raw, context);
    final typeRaw = parseStringLike(
      map['type'],
      context: '$context.type',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: true,
    );
    final type = (typeRaw == null || typeRaw.isEmpty)
        ? 'ip'
        : typeRaw.toLowerCase();

    switch (type) {
      case 'ip':
        return const RateLimitKeyConfig.ip();
      case 'header':
        final header = parseStringLike(
          map['header'],
          context: '$context.header',
          allowEmpty: false,
          coerceNonString: true,
          throwOnInvalid: true,
        );
        if (header == null || header.isEmpty) {
          throw ProviderConfigException('$context.header must be a string');
        }
        return RateLimitKeyConfig.header(header);
      default:
        throw ProviderConfigException(
          '$context.type must be one of ip or header',
        );
    }
  }

  final RateLimitKeyType type;
  final String? header;

  Map<String, dynamic> toMap() {
    return switch (type) {
      RateLimitKeyType.ip => const {'type': 'ip'},
      RateLimitKeyType.header => {'type': 'header', 'header': header},
    };
  }
}

class RateLimitPolicyConfig {
  const RateLimitPolicyConfig({
    required this.name,
    required this.match,
    required this.method,
    required this.strategy,
    required this.capacity,
    required this.interval,
    required this.window,
    required this.period,
    required this.burstMultiplier,
    required this.key,
    required this.failover,
  });

  factory RateLimitPolicyConfig.fromMap(
    Map<String, dynamic> map, {
    required String contextPath,
  }) {
    String match;
    if (!map.containsKey('match')) {
      match = '*';
    } else {
      final raw = parseStringLike(
        map['match'],
        context: '$contextPath.match',
        allowEmpty: true,
        throwOnInvalid: true,
      );
      match = (raw == null || raw.isEmpty) ? '*' : raw;
    }

    String? name;
    if (map.containsKey('name')) {
      final raw = parseStringLike(
        map['name'],
        context: '$contextPath.name',
        allowEmpty: true,
        throwOnInvalid: true,
      );
      name = (raw == null || raw.isEmpty) ? null : raw;
    }
    name ??= match.isEmpty ? '*' : match;

    String? method;
    if (map.containsKey('method')) {
      final raw = parseStringLike(
        map['method'],
        context: '$contextPath.method',
        allowEmpty: true,
        throwOnInvalid: true,
      );
      method = (raw == null || raw.isEmpty) ? null : raw;
    }

    int? intFrom(String key) => map.containsKey(key)
        ? parseIntLike(
            map[key],
            context: '$contextPath.$key',
            throwOnInvalid: true,
          )
        : null;
    Duration? durationFrom(String key) => map.containsKey(key)
        ? parseDurationLike(
            map[key],
            context: '$contextPath.$key',
            throwOnInvalid: true,
          )
        : null;

    final capacity =
        intFrom('limit') ??
        intFrom('capacity') ??
        intFrom('requests') ??
        _defaultCapacity;

    final strategy = parseStrategy(map['strategy']);
    final intervalValue = durationFrom('interval') ?? durationFrom('refill');
    final interval = intervalValue ?? _defaultInterval;
    final window = durationFrom('window') ?? intervalValue ?? _defaultWindow;
    final period = durationFrom('period') ?? intervalValue ?? _defaultPeriod;

    double? burstMultiplier;
    if (map['burst'] != null) {
      burstMultiplier = parseDoubleLike(
        map['burst'],
        context: '$contextPath.burst',
        allowEmpty: false,
        throwOnInvalid: true,
      );
      if (burstMultiplier == null) {
        throw ProviderConfigException('$contextPath.burst must be a number');
      }
    }

    final key = RateLimitKeyConfig.fromMap(
      map['key'],
      context: '$contextPath.key',
    );

    final failover = map.containsKey('failover')
        ? RateLimitConfig.parseFailover(
            map['failover'],
            context: '$contextPath.failover',
          )
        : null;

    return RateLimitPolicyConfig(
      name: name,
      match: match,
      method: method,
      strategy: strategy,
      capacity: capacity,
      interval: interval,
      window: window,
      period: period,
      burstMultiplier: burstMultiplier,
      key: key,
      failover: failover,
    );
  }

  final String name;
  final String match;
  final String? method;
  final RateLimitStrategy strategy;
  final int capacity;
  final Duration interval;
  final Duration window;
  final Duration period;
  final double? burstMultiplier;
  final RateLimitKeyConfig key;
  final RateLimitFailoverMode? failover;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'match': match,
      'method': method,
      'strategy': strategyToString(strategy),
      'capacity': capacity,
      'key': key.toMap(),
    };
    switch (strategy) {
      case RateLimitStrategy.slidingWindow:
        map['window'] = window;
        break;
      case RateLimitStrategy.quota:
        map['period'] = period;
        break;
      case RateLimitStrategy.tokenBucket:
        map['interval'] = interval;
        if (burstMultiplier != null) {
          map['burst'] = burstMultiplier;
        }
        break;
    }
    if (failover != null) {
      map['failover'] = RateLimitConfig.failoverToString(failover!);
    }
    return map;
  }

  static RateLimitStrategy parseStrategy(Object? raw) {
    final value = raw?.toString().toLowerCase().trim();
    return switch (value) {
      'sliding_window' => RateLimitStrategy.slidingWindow,
      'sliding-window' => RateLimitStrategy.slidingWindow,
      'slidingwindow' => RateLimitStrategy.slidingWindow,
      'window' => RateLimitStrategy.slidingWindow,
      'quota' => RateLimitStrategy.quota,
      'quotas' => RateLimitStrategy.quota,
      _ => RateLimitStrategy.tokenBucket,
    };
  }

  static String strategyToString(RateLimitStrategy strategy) {
    return switch (strategy) {
      RateLimitStrategy.tokenBucket => 'token_bucket',
      RateLimitStrategy.slidingWindow => 'sliding_window',
      RateLimitStrategy.quota => 'quota',
    };
  }
}

class RateLimitConfig {
  const RateLimitConfig({
    required this.enabled,
    required this.backend,
    required this.failover,
    required this.store,
    required this.policies,
  });

  factory RateLimitConfig.fromMap(Map<String, dynamic> map) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: 'rate_limit.enabled',
          throwOnInvalid: true,
        ) ??
        false;

    final backendRaw = parseStringLike(
      map['backend'],
      context: 'rate_limit.backend',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final backend = (backendRaw == null || backendRaw.isEmpty)
        ? 'memory'
        : backendRaw;

    final failover =
        parseFailover(map['failover'], context: 'rate_limit.failover') ??
        RateLimitFailoverMode.allow;

    String? store;
    if (map.containsKey('store')) {
      final storeRaw = parseStringLike(
        map['store'],
        context: 'rate_limit.store',
        allowEmpty: true,
        throwOnInvalid: true,
      );
      store = (storeRaw == null || storeRaw.isEmpty) ? null : storeRaw;
    }

    final policiesRaw = map['policies'];
    final List<RateLimitPolicyConfig> policies;
    if (policiesRaw == null) {
      policies = const <RateLimitPolicyConfig>[];
    } else {
      final parsed = parseMapList(
        policiesRaw,
        context: 'rate_limit.policies',
        throwOnInvalid: true,
      );
      policies = [
        for (var i = 0; i < parsed.length; i += 1)
          RateLimitPolicyConfig.fromMap(
            parsed[i],
            contextPath: 'rate_limit.policies[$i]',
          ),
      ];
    }

    return RateLimitConfig(
      enabled: enabled,
      backend: backend,
      failover: failover,
      store: store,
      policies: policies,
    );
  }

  final bool enabled;
  final String backend;
  final RateLimitFailoverMode failover;
  final String? store;
  final List<RateLimitPolicyConfig> policies;

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'backend': backend,
      'failover': failoverToString(failover),
      'store': store,
      'policies': policies.map((policy) => policy.toMap()).toList(),
    };
  }

  static RateLimitFailoverMode? parseFailover(
    Object? raw, {
    required String context,
  }) {
    if (raw == null) return null;
    final value = parseStringLike(
      raw,
      context: context,
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: true,
    )?.toLowerCase().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return switch (value) {
      'allow' ||
      'open' ||
      'fail_open' ||
      'fail-open' => RateLimitFailoverMode.allow,
      'block' ||
      'closed' ||
      'fail_closed' ||
      'fail-closed' => RateLimitFailoverMode.block,
      'local' ||
      'isolate' ||
      'per_instance' ||
      'per-instance' => RateLimitFailoverMode.local,
      _ => throw ProviderConfigException(
        '$context must be one of allow, block, or local',
      ),
    };
  }

  static String failoverToString(RateLimitFailoverMode mode) {
    return switch (mode) {
      RateLimitFailoverMode.allow => 'allow',
      RateLimitFailoverMode.block => 'block',
      RateLimitFailoverMode.local => 'local',
    };
  }
}

class RateLimitConfigSpec extends ConfigSpec<RateLimitConfig> {
  const RateLimitConfigSpec();

  @override
  String get root => 'rate_limit';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Rate Limit Configuration',
    description: 'HTTP rate limiting and throttling settings.',
    properties: {
      'enabled': ConfigSchema.boolean(
        description: 'Enable rate limiting middleware.',
        defaultValue: false,
      ),
      'backend': ConfigSchema.string(
        description:
            'Backend hint ("memory" uses array store, "redis" expects a Redis-backed cache store).',
        defaultValue: 'memory',
      ),
      'failover': ConfigSchema.string(
        description:
            'Failover mode when the backing store is unavailable (allow, block, local).',
        options: ['allow', 'block', 'local'],
        defaultValue: 'allow',
      ),
      'store': ConfigSchema.string(
        description:
            'Cache store name to use for rate limit counters (defaults to cache.default).',
      ),
      'policies': ConfigSchema.list(
        description: 'Array of rate limit policies (match, capacity, key).',
        items: ConfigSchema.object(
          properties: {
            'name': ConfigSchema.string(),
            'match': ConfigSchema.string(defaultValue: '*'),
            'method': ConfigSchema.string(),
            'strategy': ConfigSchema.string(
              description:
                  'Enforcement strategy (token_bucket, sliding_window, quota).',
              options: ['token_bucket', 'sliding_window', 'quota'],
              defaultValue: 'token_bucket',
            ),
            'limit': ConfigSchema.integer(),
            'capacity': ConfigSchema.integer(),
            'requests': ConfigSchema.integer(),
            'interval': ConfigSchema.duration(),
            'refill': ConfigSchema.duration(),
            'window': ConfigSchema.duration(
              description:
                  'Sliding window duration when using the sliding_window strategy.',
            ),
            'period': ConfigSchema.duration(
              description:
                  'Quota reset interval when using the quota strategy.',
            ),
            'burst': ConfigSchema.number(),
            'key': ConfigSchema.object(
              properties: {
                'type': ConfigSchema.string(
                  options: ['ip', 'header'],
                  defaultValue: 'ip',
                ),
                'header': ConfigSchema.string(),
              },
            ),
            'failover': ConfigSchema.string(
              options: ['allow', 'block', 'local'],
            ),
          },
        ),
        defaultValue: const [],
      ),
    },
  );

  @override
  RateLimitConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    return RateLimitConfig.fromMap(map);
  }

  @override
  Map<String, dynamic> toMap(RateLimitConfig value) {
    return value.toMap();
  }
}
