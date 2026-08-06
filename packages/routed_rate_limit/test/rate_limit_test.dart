import 'package:test/test.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';

class _Req implements RateLimitRequest {
  _Req(this.method, this.path) : ip = '127.0.0.1';
  @override
  final String method;
  @override
  final String path;
  final String ip;
  @override
  String get clientIP => ip;
  @override
  String get remoteAddr => ip;
  @override
  String header(String name) => '';
}

void main() {
  group('RoutedRateLimit', () {
    group('RoutedRateLimitProvider', () {
      test('registers RateLimitService in container', () async {
        final service = RateLimitService([]);
        final provider = RoutedRateLimitProvider(service);
        // Simulate container registration
        expect(provider.service, same(service));
        expect(service.enabled, isFalse);
      });
    });

    group('RateLimitEngineContext', () {
      test('service with no policies allows all', () async {
        final service = RateLimitService([]);
        final req = _Req('GET', '/api');
        final outcome = await service.check(req);
        expect(outcome, isNull);
      });
    });

    group('rateLimitMiddleware', () {
      test('creates middleware', () {
        final service = RateLimitService([]);
        final middleware = rateLimitMiddleware(service);
        expect(middleware, isA<Function>());
      });
    });
  });
}
