import 'package:routed_core/routed_core.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:test/test.dart';

class _BlockingBackend implements RateLimiterBackend {
  @override
  Future<RateLimitOutcome> consume(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now, {
    RateLimitFailoverMode failover = RateLimitFailoverMode.allow,
  }) async {
    return RateLimitOutcome.blocked(
      retryAfter: const Duration(seconds: 4),
      remaining: 0,
      failoverMode: failover,
    );
  }

  @override
  Future<void> close() async {}
}

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
        final provider = RoutedRateLimitProvider(
          RateLimitConfig(service: service),
        );
        // Simulate container registration
        expect(provider.configuration.service, same(service));
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

      test('returns 429 and Retry-After when a policy blocks', () async {
        final service = RateLimitService(
          compileRateLimitPolicies(
            specs: [
              const RateLimitPolicySpec(
                name: 'all',
                match: '**',
                method: null,
                strategy: RateLimitStrategy.tokenBucket,
                capacity: 1,
                interval: Duration(seconds: 1),
                window: Duration.zero,
                period: Duration.zero,
                burstMultiplier: null,
                key: RateLimitKeySpec.ip(),
              ),
            ],
            backend: _BlockingBackend(),
            defaultFailover: RateLimitFailoverMode.allow,
          ),
        );
        final engine = Engine(
          providers: [
            RoutedRateLimitProvider(RateLimitConfig(service: service)),
          ],
          middlewares: [rateLimitMiddleware(service)],
        )..get('/limited', (ctx) => ctx.string('ok'));
        await engine.initialize();
        addTearDown(engine.close);

        final response = await engine.handlePortable(
          PortableRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test/limited'),
          ),
        );

        expect(response.statusCode, HttpStatus.tooManyRequests);
        expect(response.headers.get(HttpHeaders.retryAfterHeader), '4');
        expect(response.bodyText, 'Too Many Requests');
      });
    });

    group('RoutedAuthRateLimiter', () {
      test(
        'uses the existing request service and returns its decision',
        () async {
          final service = RateLimitService(
            compileRateLimitPolicies(
              specs: [
                const RateLimitPolicySpec(
                  name: 'auth',
                  match: '/auth/signin/**',
                  method: 'POST',
                  strategy: RateLimitStrategy.tokenBucket,
                  capacity: 1,
                  interval: Duration(seconds: 1),
                  window: Duration.zero,
                  period: Duration.zero,
                  burstMultiplier: null,
                  key: RateLimitKeySpec.ip(),
                ),
              ],
              backend: _BlockingBackend(),
              defaultFailover: RateLimitFailoverMode.allow,
            ),
          );
          final limiter = RoutedAuthRateLimiter(service);
          final engine = Engine()
            ..post('/auth/signin/credentials', (ctx) async {
              final decision = await limiter.check(
                AuthRateLimitRequest<EngineContext>(
                  action: AuthRateLimitAction.signIn,
                  providerId: 'credentials',
                  context: ctx,
                  identifier: 'alice',
                ),
              );
              return ctx.json(<String, dynamic>{'allowed': decision.allowed});
            });
          await engine.initialize();
          addTearDown(engine.close);

          final response = await engine.handlePortable(
            PortableRequest(
              method: 'POST',
              uri: Uri.parse('https://example.test/auth/signin/credentials'),
            ),
          );

          expect(response.statusCode, HttpStatus.ok);
          expect(response.bodyText, '{"allowed":false}');
        },
      );
    });
  });
}
