import 'package:server_data/server_data.dart';
import 'package:test/test.dart';

class _FakeRequest implements RateLimitRequest {
  _FakeRequest({
    required this.method,
    required this.path,
    this.clientIP = '',
    this.remoteAddr = '',
    Map<String, String>? headers,
  }) : _headers = headers ?? <String, String>{};

  @override
  final String method;

  @override
  final String path;

  @override
  final String clientIP;

  @override
  final String remoteAddr;

  final Map<String, String> _headers;

  @override
  String header(String name) => _headers[name] ?? '';
}

void main() {
  group('CacheRateLimiterBackend', () {
    late CacheRateLimiterBackend backend;
    late TokenBucketConfig bucket;
    late DateTime base;

    setUp(() {
      final repository = RepositoryImpl(ArrayStore(), 'rate', '');
      backend = CacheRateLimiterBackend(repository: repository);
      bucket = buildBucketConfig(
        capacity: 2,
        refillInterval: const Duration(seconds: 30),
      );
      base = DateTime.now();
    });

    tearDown(() async {
      await backend.close();
    });

    test('enforces capacity then allows after refill', () async {
      final first = await backend.consume('ip:1', bucket, base);
      final second = await backend.consume('ip:1', bucket, base);
      final blocked = await backend.consume('ip:1', bucket, base);

      expect(first.allowed, isTrue);
      expect(second.allowed, isTrue);
      expect(blocked.allowed, isFalse);

      final afterRefill = await backend.consume(
        'ip:1',
        bucket,
        base.add(const Duration(seconds: 40)),
      );
      expect(afterRefill.allowed, isTrue);
    });

    test('supports quota strategy', () async {
      final quota = QuotaConfig(limit: 1, period: const Duration(hours: 1));
      final first = await backend.consume('quota:user', quota, base);
      final blocked = await backend.consume('quota:user', quota, base);

      expect(first.allowed, isTrue);
      expect(blocked.allowed, isFalse);
      expect(blocked.retryAfter, greaterThan(Duration.zero));
    });
  });

  group('RateLimitService', () {
    test('emits callbacks for allowed and blocked outcomes', () async {
      final backend = CacheRateLimiterBackend(
        repository: RepositoryImpl(ArrayStore(), 'rate', ''),
      );

      final policy = CompiledRateLimitPolicy(
        name: 'header-policy',
        matcher: RequestMatcher(method: 'GET', pattern: '*'),
        keyResolver: const HeaderKeyResolver('x-user-id'),
        algorithm: buildBucketConfig(
          capacity: 1,
          refillInterval: const Duration(minutes: 1),
        ),
        backend: backend,
        failover: RateLimitFailoverMode.allow,
      );

      final allowed = <String>[];
      final blocked = <String>[];
      final service = RateLimitService(
        [policy],
        callbacks: RateLimitEventCallbacks(
          onAllowed: (p, _, id, _, _) => allowed.add('$p:$id'),
          onBlocked: (p, _, id, _, _, _) => blocked.add('$p:$id'),
        ),
      );

      final request = _FakeRequest(
        method: 'GET',
        path: '/resource',
        clientIP: '127.0.0.1',
        remoteAddr: '127.0.0.1',
        headers: {'x-user-id': 'user-123'},
      );

      final first = await service.check(request);
      final second = await service.check(request);

      expect(first, isNull);
      expect(second, isNotNull);
      expect(second!.allowed, isFalse);
      expect(allowed, equals(['header-policy:user-123']));
      expect(blocked, equals(['header-policy:user-123']));

      await service.dispose();
    });
  });

  group('rate limit compiler', () {
    test('compiles policies with default failover', () async {
      final backend = CacheRateLimiterBackend(
        repository: RepositoryImpl(ArrayStore(), 'rate', ''),
      );

      final policies = compileRateLimitPolicies(
        specs: [
          const RateLimitPolicySpec(
            name: 'compiled',
            match: '/api/*',
            method: 'GET',
            strategy: RateLimitStrategy.tokenBucket,
            capacity: 1,
            interval: Duration(minutes: 1),
            window: Duration(minutes: 1),
            period: Duration(hours: 1),
            burstMultiplier: null,
            key: RateLimitKeySpec.header('x-user'),
            failover: null,
          ),
        ],
        backend: backend,
        defaultFailover: RateLimitFailoverMode.block,
      );

      final request = _FakeRequest(
        method: 'GET',
        path: '/api/users',
        headers: {'x-user': 'user-1'},
      );

      expect(policies, hasLength(1));
      expect(policies.first.matches(request), isTrue);
      expect(policies.first.keyResolver.resolve(request), equals('user-1'));
      expect(policies.first.failover, equals(RateLimitFailoverMode.block));

      await backend.close();
    });

    test('falls back to ip resolver for blank header key specs', () {
      final resolver = buildRateLimitKeyResolver(
        const RateLimitKeySpec.header('   '),
      );
      final request = _FakeRequest(
        method: 'GET',
        path: '/',
        clientIP: '192.168.1.10',
      );

      expect(resolver.resolve(request), equals('192.168.1.10'));
    });

    test('normalizes min capacity across strategies', () async {
      final backend = CacheRateLimiterBackend(
        repository: RepositoryImpl(ArrayStore(), 'rate', ''),
      );

      final token = compileRateLimitPolicy(
        spec: const RateLimitPolicySpec(
          name: 'token',
          match: '*',
          method: null,
          strategy: RateLimitStrategy.tokenBucket,
          capacity: 0,
          interval: Duration(seconds: 30),
          window: Duration(minutes: 1),
          period: Duration(hours: 1),
          burstMultiplier: null,
          key: RateLimitKeySpec.ip(),
          failover: null,
        ),
        backend: backend,
        defaultFailover: RateLimitFailoverMode.allow,
      );
      final tokenConfig = token.algorithm as TokenBucketConfig;
      expect(tokenConfig.capacity, equals(1));

      final sliding = compileRateLimitPolicy(
        spec: const RateLimitPolicySpec(
          name: 'sliding',
          match: '*',
          method: null,
          strategy: RateLimitStrategy.slidingWindow,
          capacity: 0,
          interval: Duration(seconds: 30),
          window: Duration(minutes: 1),
          period: Duration(hours: 1),
          burstMultiplier: null,
          key: RateLimitKeySpec.ip(),
          failover: null,
        ),
        backend: backend,
        defaultFailover: RateLimitFailoverMode.allow,
      );
      final slidingConfig = sliding.algorithm as SlidingWindowConfig;
      expect(slidingConfig.limit, equals(1));

      final quota = compileRateLimitPolicy(
        spec: const RateLimitPolicySpec(
          name: 'quota',
          match: '*',
          method: null,
          strategy: RateLimitStrategy.quota,
          capacity: 0,
          interval: Duration(seconds: 30),
          window: Duration(minutes: 1),
          period: Duration(hours: 1),
          burstMultiplier: null,
          key: RateLimitKeySpec.ip(),
          failover: null,
        ),
        backend: backend,
        defaultFailover: RateLimitFailoverMode.allow,
      );
      final quotaConfig = quota.algorithm as QuotaConfig;
      expect(quotaConfig.limit, equals(1));

      await backend.close();
    });
  });
}
