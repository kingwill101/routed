import 'dart:async';
import 'dart:math';

import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/config/specs/cache.dart';
import 'package:routed/src/config/specs/rate_limit.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
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
  static const RateLimitConfigSpec spec = RateLimitConfigSpec();
  static const CacheConfigSpec cacheSpec = CacheConfigSpec();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.rate_limit': {
          'global': ['routed.rate_limit.middleware'],
        },
      },
    };

    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description:
              'Rate limiting middleware references registered globally.',
          defaultValue: <String, Object?>{
            'routed.rate_limit': <String, Object?>{
              'global': <String>['routed.rate_limit.middleware'],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
      schemas: spec.schemaWithRoot(),
    );
  }

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
    final resolved = spec.resolve(config);

    if (!resolved.enabled) {
      return RateLimitService(const []);
    }

    final backend = await _createBackend(resolved, config);
    final policies = _compilePolicies(resolved, backend);
    EventManager? events;
    if (container.has<EventManager>()) {
      events = await container.make<EventManager>();
    }
    return RateLimitService(policies, events: events);
  }

  Future<RateLimiterBackend> _createBackend(
    RateLimitConfig resolved,
    Config config,
  ) async {
    final manager = _cacheManager ??= CacheManager();

    final configuredStore = resolved.store;
    final cacheConfig = cacheSpec.resolve(config);
    final defaultStoreName = configuredStore ?? cacheConfig.defaultStore;

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
    RateLimitConfig config,
    RateLimiterBackend backend,
  ) {
    if (config.policies.isEmpty) {
      return const [];
    }
    final defaultFailover = config.failover;
    return config.policies
        .map((policy) => _compilePolicy(policy, backend, defaultFailover))
        .toList(growable: false);
  }

  CompiledRateLimitPolicy _compilePolicy(
    RateLimitPolicyConfig policy,
    RateLimiterBackend backend,
    RateLimitFailoverMode defaultFailover,
  ) {
    final RateLimitAlgorithmConfig algorithm;
    switch (policy.strategy) {
      case RateLimitStrategy.slidingWindow:
        algorithm = SlidingWindowConfig(
          limit: max(1, policy.capacity),
          window: policy.window,
        );
        break;
      case RateLimitStrategy.quota:
        algorithm = QuotaConfig(
          limit: max(1, policy.capacity),
          period: policy.period,
        );
        break;
      case RateLimitStrategy.tokenBucket:
        algorithm = buildBucketConfig(
          capacity: policy.capacity,
          refillInterval: policy.interval,
          burstMultiplier: policy.burstMultiplier,
        );
        break;
    }

    final keyResolver = _buildKeyResolver(policy.key);
    final matcher = RequestMatcher(
      method: policy.method,
      pattern: policy.match,
    );
    final failover = policy.failover ?? defaultFailover;

    return CompiledRateLimitPolicy(
      name: policy.name,
      matcher: matcher,
      keyResolver: keyResolver,
      algorithm: algorithm,
      backend: backend,
      failover: failover,
    );
  }

  RateLimitKeyResolver _buildKeyResolver(RateLimitKeyConfig key) {
    switch (key.type) {
      case RateLimitKeyType.ip:
        return const IpKeyResolver();
      case RateLimitKeyType.header:
        final header = key.header ?? '';
        return HeaderKeyResolver(header);
    }
  }
}
