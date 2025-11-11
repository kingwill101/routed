import 'dart:async';
import 'dart:math';

import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../../events/event_manager.dart';
import '../../middleware/rate_limit.dart';
import '../../rate_limit/backend.dart';
import '../../rate_limit/policy.dart';
import '../../rate_limit/service.dart';

class RateLimitServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  RateLimitServiceProvider();

  RateLimitService _service = RateLimitService(const []);
  CacheManager? _cacheManager;

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: [
      ConfigDocEntry(
        path: 'rate_limit.enabled',
        type: 'bool',
        description: 'Enable rate limiting middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'rate_limit.backend',
        type: 'string',
        description:
            'Backend hint ("memory" uses array store, "redis" expects a Redis-backed cache store).',
        defaultValue: 'memory',
      ),
      ConfigDocEntry(
        path: 'rate_limit.failover',
        type: 'string',
        description:
            'Failover mode when the backing store is unavailable (allow, block, local).',
        options: ['allow', 'block', 'local'],
        defaultValue: 'allow',
      ),
      ConfigDocEntry(
        path: 'rate_limit.store',
        type: 'string',
        description:
            'Cache store name to use for rate limit counters (defaults to cache.default).',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'rate_limit.policies',
        type: 'list<object>',
        description: 'Array of rate limit policies (match, capacity, key).',
        defaultValue: <Map<String, dynamic>>[],
      ),
      ConfigDocEntry(
        path: 'rate_limit.policies[].strategy',
        type: 'string',
        description:
            'Enforcement strategy (token_bucket, sliding_window, quota).',
        options: ['token_bucket', 'sliding_window', 'quota'],
      ),
      ConfigDocEntry(
        path: 'rate_limit.policies[].window',
        type: 'duration',
        description:
            'Sliding window duration when using the sliding_window strategy.',
      ),
      ConfigDocEntry(
        path: 'rate_limit.policies[].period',
        type: 'duration',
        description: 'Quota reset interval when using the quota strategy.',
      ),
      ConfigDocEntry(
        path: 'http.middleware_sources',
        type: 'map',
        description: 'Rate limiting middleware references registered globally.',
        defaultValue: <String, Object?>{
          'routed.rate_limit': <String, Object?>{
            'global': <String>['routed.rate_limit.middleware'],
          },
        },
      ),
    ],
  );

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'routed.rate_limit.middleware',
      (_) => rateLimitMiddleware(_service),
    );
    if (container.has<CacheManager>()) {
      _cacheManager = container.get<CacheManager>();
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) return;
    if (container.has<CacheManager>()) {
      _cacheManager = container.get<CacheManager>();
    }
    await _rebuild(container, container.get<Config>());
    container.instance<RateLimitService>(_service);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    if (container.has<CacheManager>()) {
      _cacheManager = container.get<CacheManager>();
    }
    await _rebuild(container, config);
    container.instance<RateLimitService>(_service);
  }

  Future<void> _rebuild(Container container, Config config) async {
    final newService = await _buildService(container, config);
    final oldService = _service;
    _service = newService;
    await oldService.dispose();
  }

  Future<RateLimitService> _buildService(
    Container container,
    Config config,
  ) async {
    final enabled =
        parseBoolLike(
          config.get('rate_limit.enabled'),
          context: 'rate_limit.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        false;

    if (!enabled) {
      return RateLimitService(const []);
    }

    final backend = await _createBackend(config);
    final defaultFailover =
        _parseFailover(
          config.get('rate_limit.failover'),
          context: 'rate_limit.failover',
        ) ??
        RateLimitFailoverMode.allow;
    final policies = _compilePolicies(config, backend, defaultFailover);
    EventManager? events;
    if (container.has<EventManager>()) {
      events = await container.make<EventManager>();
    }
    return RateLimitService(policies, events: events);
  }

  Future<RateLimiterBackend> _createBackend(Config config) async {
    final manager = _cacheManager ??= CacheManager();

    final configuredStore = parseStringLike(
      config.get('rate_limit.store'),
      context: 'rate_limit.store',
      throwOnInvalid: false,
    );

    final defaultStoreName =
        configuredStore ??
        parseStringLike(
          config.get('cache.default'),
          context: 'cache.default',
          throwOnInvalid: false,
        );

    if (defaultStoreName == null || defaultStoreName.isEmpty) {
      throw ProviderConfigException(
        'rate_limit.store is not set and cache.default is missing; configure a cache store for the rate limiter.',
      );
    }

    final Repository repository;
    try {
      repository = manager.store(defaultStoreName);
    } on ArgumentError {
      throw ProviderConfigException(
        'Cache store "$defaultStoreName" is not defined. Configure it under cache.stores or set rate_limit.store to an existing store.',
      );
    }

    return CacheRateLimiterBackend(repository: repository);
  }

  List<CompiledRateLimitPolicy> _compilePolicies(
    Config config,
    RateLimiterBackend backend,
    RateLimitFailoverMode defaultFailover,
  ) {
    final rawPolicies =
        config.get('rate_limit.policies') as List<dynamic>? ?? const [];
    if (rawPolicies.isEmpty) {
      return const [];
    }

    return rawPolicies
        .map((raw) => _parsePolicy(raw, backend, defaultFailover))
        .whereType<CompiledRateLimitPolicy>()
        .toList(growable: false);
  }

  CompiledRateLimitPolicy? _parsePolicy(
    dynamic raw,
    RateLimiterBackend backend,
    RateLimitFailoverMode defaultFailover,
  ) {
    if (raw is! Map) return null;
    final map = stringKeyedMap(raw, 'rate_limit.policy');
    final name = map['name']?.toString() ?? map['match']?.toString() ?? '*';
    final match = map['match']?.toString() ?? '*';
    final method = map['method']?.toString();
    final capacity =
        parseIntLike(
          map['limit'],
          context: '$name.limit',
          throwOnInvalid: false,
        ) ??
        parseIntLike(
          map['capacity'],
          context: '$name.capacity',
          throwOnInvalid: false,
        ) ??
        parseIntLike(
          map['requests'],
          context: '$name.requests',
          throwOnInvalid: false,
        ) ??
        100;
    final intervalValue = map['interval'] ?? map['refill'];
    final strategy = _parseStrategy(map['strategy']);
    final RateLimitAlgorithmConfig algorithm;
    switch (strategy) {
      case RateLimitStrategy.slidingWindow:
        final limit = capacity;
        final window =
            parseDurationLike(
              map['window'] ?? intervalValue,
              context: '$name.window',
              throwOnInvalid: false,
            ) ??
            const Duration(minutes: 1);
        algorithm = SlidingWindowConfig(limit: max(1, limit), window: window);
        break;
      case RateLimitStrategy.quota:
        final limit = capacity;
        final period =
            _parseExtendedDuration(
              map['period'] ?? intervalValue,
              context: '$name.period',
              throwOnInvalid: false,
            ) ??
            const Duration(hours: 24);
        algorithm = QuotaConfig(limit: max(1, limit), period: period);
        break;
      case RateLimitStrategy.tokenBucket:
        final interval =
            parseDurationLike(
              intervalValue,
              context: '$name.interval',
              throwOnInvalid: false,
            ) ??
            const Duration(minutes: 1);
        final burst = map['burst'] is num
            ? (map['burst'] as num).toDouble()
            : double.tryParse(map['burst']?.toString() ?? '');
        algorithm = buildBucketConfig(
          capacity: capacity,
          refillInterval: interval,
          burstMultiplier: burst,
        );
        break;
    }

    final keySource = map['key'] ?? <String, dynamic>{'type': 'ip'};
    final keyConfig = stringKeyedMap(keySource as Object, '$name.key');
    final resolver = _buildKeyResolver(name, keyConfig);
    if (resolver == null) return null;

    final matcher = RequestMatcher(method: method, pattern: match);
    final failover = map.containsKey('failover')
        ? _parseFailover(map['failover'], context: '$name.failover') ??
              defaultFailover
        : defaultFailover;

    return CompiledRateLimitPolicy(
      name: name,
      matcher: matcher,
      keyResolver: resolver,
      algorithm: algorithm,
      backend: backend,
      failover: failover,
    );
  }

  RateLimitKeyResolver? _buildKeyResolver(
    String name,
    Map<String, dynamic> config,
  ) {
    final type = config['type']?.toString().toLowerCase() ?? 'ip';
    switch (type) {
      case 'ip':
        return const IpKeyResolver();
      case 'header':
        final header = config['header']?.toString();
        if (header == null || header.isEmpty) {
          return null;
        }
        return HeaderKeyResolver(header);
      default:
        return null;
    }
  }

  RateLimitStrategy _parseStrategy(Object? raw) {
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

  RateLimitFailoverMode? _parseFailover(
    Object? raw, {
    required String context,
  }) {
    if (raw == null) return null;
    final value = raw.toString().toLowerCase().trim();
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
}

Duration? _parseExtendedDuration(
  Object? value, {
  required String context,
  bool throwOnInvalid = true,
}) {
  final base = parseDurationLike(
    value,
    context: context,
    throwOnInvalid: false,
  );
  if (base != null) {
    return base;
  }
  if (value == null) {
    return null;
  }

  final raw = value.toString().trim().toLowerCase();
  if (raw.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^(?<amount>-?\d+(?:\.\d+)?)(?<unit>d|day|days|w|week|weeks|mo|month|months|y|year|years)$',
  ).firstMatch(raw);
  if (match == null) {
    if (throwOnInvalid) {
      throw ProviderConfigException(
        '$context must be a duration (supports ms, s, m, h, d, w, mo, y)',
      );
    }
    return null;
  }

  final amount = double.tryParse(match.namedGroup('amount') ?? '');
  if (amount == null) {
    if (throwOnInvalid) {
      throw ProviderConfigException('$context must be a duration value');
    }
    return null;
  }
  final unit = match.namedGroup('unit')!;
  const dayMs = 24 * 60 * 60 * 1000;
  final milliseconds = switch (unit) {
    'd' || 'day' || 'days' => amount * dayMs,
    'w' || 'week' || 'weeks' => amount * dayMs * 7,
    'mo' || 'month' || 'months' => amount * dayMs * 30,
    'y' || 'year' || 'years' => amount * dayMs * 365,
    _ => amount * 1000,
  };
  return Duration(milliseconds: milliseconds.round());
}
