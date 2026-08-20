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

class _CapturingBackend implements RateLimiterBackend {
  final List<String> bucketKeys = <String>[];

  @override
  Future<RateLimitOutcome> consume(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now, {
    RateLimitFailoverMode failover = RateLimitFailoverMode.allow,
  }) async {
    bucketKeys.add(bucketKey);
    return RateLimitOutcome.allowed(remaining: 1, failoverMode: failover);
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
                AuthRateLimitRequest<EngineContext>.operation(
                  operation: AuthRateLimitOperation.core(
                    AuthRateLimitAction.signIn,
                  ),
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

      test(
        'preserves operation, namespace, identifier, and request metadata',
        () async {
          final backend = _CapturingBackend();
          final observed = <RoutedAuthRateLimitRequest>[];
          final service = RateLimitService(<CompiledRateLimitPolicy>[
            CompiledRateLimitPolicy(
              name: 'auth-plugin',
              matcher: RequestMatcher(method: 'POST', pattern: '/auth/plugin'),
              keyResolver: CustomResolver((request) {
                expect(request, isA<RoutedAuthRateLimitRequest>());
                final authRequest = request as RoutedAuthRateLimitRequest;
                observed.add(authRequest);
                return <String>[
                  authRequest.providerId,
                  authRequest.operation.id,
                  authRequest.identifier ?? 'none',
                ].join(':');
              }),
              algorithm: buildBucketConfig(
                capacity: 2,
                refillInterval: const Duration(minutes: 1),
              ),
              backend: backend,
              failover: RateLimitFailoverMode.allow,
            ),
          ]);
          final limiter = RoutedAuthRateLimiter(service);
          final engine = Engine()
            ..post('/auth/plugin', (ctx) async {
              for (final request in <AuthRateLimitRequest<EngineContext>>[
                AuthRateLimitRequest<EngineContext>.operation(
                  operation: const AuthRateLimitOperation(
                    'phone_number',
                    'send_code',
                  ),
                  providerId: 'phone_number',
                  context: ctx,
                  identifier: 'phone:keyed-hash',
                ),
                AuthRateLimitRequest<EngineContext>.operation(
                  operation: const AuthRateLimitOperation(
                    'username',
                    'sign_in',
                  ),
                  providerId: 'username',
                  context: ctx,
                  identifier: 'routed.user',
                ),
                AuthRateLimitRequest<EngineContext>.operation(
                  operation: const AuthRateLimitOperation(
                    'username',
                    'sign_in',
                  ),
                  providerId: 'username',
                  context: ctx,
                ),
              ]) {
                await limiter.check(request);
              }
              return ctx.string('ok');
            });
          await engine.initialize();
          addTearDown(engine.close);

          final response = await engine.handlePortable(
            PortableRequest(
              method: 'POST',
              uri: Uri.parse('https://example.test/auth/plugin'),
            ),
          );

          expect(response.statusCode, HttpStatus.ok);
          expect(observed, hasLength(3));
          expect(observed.first.method, 'POST');
          expect(observed.first.path, '/auth/plugin');
          expect(observed.first.providerId, 'phone_number');
          expect(observed.first.operation.id, 'phone_number.send_code');
          expect(observed.first.identifier, 'phone:keyed-hash');
          expect(observed.last.identifier, isNull);
          expect(backend.bucketKeys, <String>[
            'auth-plugin:phone_number:phone_number.send_code:phone:keyed-hash',
            'auth-plugin:username:username.sign_in:routed.user',
            'auth-plugin:username:username.sign_in:none',
          ]);
          expect(backend.bucketKeys[0], isNot(equals(backend.bucketKeys[1])));
        },
      );
    });
  });
}
