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
}
