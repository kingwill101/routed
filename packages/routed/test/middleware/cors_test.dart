import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('corsMiddleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        test('echoes wildcard origin when credentials are disabled', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(
                  enabled: true,
                  allowedOrigins: ['*'],
                  allowCredentials: false,
                ),
              ),
            ),
          )..get('/ping', (ctx) => ctx.string('pong'));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);
          final response = await client.get(
            '/ping',
            headers: {
              'Origin': ['https://client.dev'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertHeader('Access-Control-Allow-Origin', '*')
            ..assertHeaderContains('Access-Control-Allow-Methods', ['GET']);
        });

        test(
          'reflects origin when credentials enabled with wildcard',
          () async {
            final engine = Engine(
              config: EngineConfig(
                security: const EngineSecurityFeatures(
                  cors: CorsConfig(
                    enabled: true,
                    allowedOrigins: ['*'],
                    allowCredentials: true,
                  ),
                ),
              ),
            )..get('/ping', (ctx) => ctx.string('pong'));

            final client = TestClient(RoutedRequestHandler(engine), mode: mode);
            addTearDown(client.close);
            addTearDown(engine.close);
            final response = await client.get(
              '/ping',
              headers: {
                'Origin': ['https://client.dev'],
              },
            );
            response
              ..assertStatus(HttpStatus.ok)
              ..assertHeader(
                'Access-Control-Allow-Origin',
                'https://client.dev',
              )
              ..assertHeaderContains('Vary', ['Origin'])
              ..assertHeader('Access-Control-Allow-Credentials', 'true');
          },
        );

        test('rejects disallowed origins', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(
                  enabled: true,
                  allowedOrigins: ['https://allowed.dev'],
                ),
              ),
            ),
          )..get('/ping', (ctx) => ctx.string('pong'));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);
          final response = await client.get(
            '/ping',
            headers: {
              'Origin': ['https://evil.dev'],
            },
          );
          response
            ..assertStatus(HttpStatus.forbidden)
            ..assertBodyContains('CORS origin check failed');
        });

        test('allows specific origins', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(
                  enabled: true,
                  allowedOrigins: ['https://app1.dev', 'https://app2.dev'],
                ),
              ),
            ),
          )..get('/data', (ctx) => ctx.json({'data': 'ok'}));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);

          // Test allowed origin 1
          final response1 = await client.get(
            '/data',
            headers: {
              'Origin': ['https://app1.dev'],
            },
          );
          response1
            ..assertStatus(HttpStatus.ok)
            ..assertHeader('Access-Control-Allow-Origin', 'https://app1.dev');

          // Test allowed origin 2
          final response2 = await client.get(
            '/data',
            headers: {
              'Origin': ['https://app2.dev'],
            },
          );
          response2
            ..assertStatus(HttpStatus.ok)
            ..assertHeader('Access-Control-Allow-Origin', 'https://app2.dev');
        });

        test('origin negotiation respects configuration (property)', () async {
          final runner = PropertyTestRunner<_CorsSample>(_corsSampleGen(), (
            sample,
          ) async {
            final engine = Engine(
              config: EngineConfig(
                security: EngineSecurityFeatures(
                  cors: CorsConfig(
                    enabled: true,
                    allowedOrigins: sample.allowedOrigins,
                    allowCredentials: sample.allowCredentials,
                  ),
                ),
              ),
            )..get('/ping', (ctx) => ctx.string('pong'));

            final client = TestClient(RoutedRequestHandler(engine), mode: mode);
            final response = await client.get(
              '/ping',
              headers: {
                'Origin': [sample.requestOrigin],
              },
            );

            if (sample.expectAllowed) {
              response.assertStatus(HttpStatus.ok);
              final expectedOrigin =
                  sample.allowedOrigins.contains('*') &&
                      !sample.allowCredentials
                  ? '*'
                  : sample.requestOrigin;
              response.assertHeader(
                'Access-Control-Allow-Origin',
                expectedOrigin,
              );
              if (sample.allowCredentials) {
                response.assertHeader(
                  'Access-Control-Allow-Credentials',
                  'true',
                );
                response.assertHeaderContains('Vary', ['Origin']);
              } else {
                expect(
                  response.headers.containsKey(
                    'Access-Control-Allow-Credentials',
                  ),
                  isFalse,
                );
              }
            } else {
              response
                ..assertStatus(HttpStatus.forbidden)
                ..assertBodyContains('CORS origin check failed');
            }

            await client.close();
            await engine.close();
          }, PropertyConfig(numTests: 30, seed: 20250314));

          final result = await runner.run();
          expect(result.success, isTrue, reason: result.report);
        });

        test('handles preflight OPTIONS request', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(
                  enabled: true,
                  allowedOrigins: ['https://client.dev'],
                  allowedMethods: ['GET', 'POST', 'PUT'],
                  allowedHeaders: ['Content-Type', 'Authorization'],
                ),
              ),
            ),
          )..post('/api/resource', (ctx) => ctx.json({'created': true}));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);
          final response = await client.options(
            '/api/resource',
            headers: {
              'Origin': ['https://client.dev'],
              'Access-Control-Request-Method': ['POST'],
              'Access-Control-Request-Headers': ['Content-Type'],
            },
          );
          response
            ..assertStatus(HttpStatus.noContent)
            ..assertHeader('Access-Control-Allow-Origin', 'https://client.dev')
            ..assertHeaderContains('Access-Control-Allow-Methods', ['POST']);
        });

        test('does not set CORS headers when CORS is disabled', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(enabled: false),
              ),
            ),
          )..get('/data', (ctx) => ctx.string('data'));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);
          final response = await client.get(
            '/data',
            headers: {
              'Origin': ['https://any.dev'],
            },
          );
          response.assertStatus(HttpStatus.ok);
          // Should not have CORS headers
          expect(
            response.headers.containsKey('Access-Control-Allow-Origin'),
            isFalse,
          );
        });

        test('sets max age for preflight cache', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(
                  enabled: true,
                  allowedOrigins: ['*'],
                  maxAge: 3600,
                ),
              ),
            ),
          )..get('/test', (ctx) => ctx.string('ok'));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);
          final response = await client.options(
            '/test',
            headers: {
              'Origin': ['https://client.dev'],
              'Access-Control-Request-Method': ['GET'],
            },
          );
          response.assertHeader('Access-Control-Max-Age', '3600');
        });

        test('exposes custom headers', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                cors: CorsConfig(
                  enabled: true,
                  allowedOrigins: ['*'],
                  exposedHeaders: ['X-Custom-Header', 'X-Request-ID'],
                ),
              ),
            ),
          )..get('/api', (ctx) => ctx.json({'status': 'ok'}));

          final client = TestClient(RoutedRequestHandler(engine), mode: mode);
          addTearDown(client.close);
          addTearDown(engine.close);
          final response = await client.get(
            '/api',
            headers: {
              'Origin': ['https://client.dev'],
            },
          );
          response.assertHeaderContains('Access-Control-Expose-Headers', [
            'X-Custom-Header',
          ]);
        });
      });
    }
  });
}

typedef _CorsSample = ({
  List<String> allowedOrigins,
  bool allowCredentials,
  String requestOrigin,
  bool expectAllowed,
});

const _originPool = <String>{
  'https://app1.dev',
  'https://app2.dev',
  'https://client.dev',
  'https://evil.dev',
  'https://partner.dev',
};

Generator<_CorsSample> _corsSampleGen() {
  final originsList = _originPool.toList();
  final allCandidates = <String>[...originsList, 'https://unlisted.dev'];

  final specificOrigins = Gen.someOf(
    originsList,
    min: 0,
    max: originsList.length,
  );

  return Gen.boolean().flatMap((includeWildcard) {
    return specificOrigins.flatMap((specific) {
      final allowed = <String>[if (includeWildcard) '*', ...specific];

      return Gen.boolean().flatMap((allowCredentials) {
        if (includeWildcard) {
          return Gen.oneOf(originsList).map(
            (origin) => (
              allowedOrigins: allowed,
              allowCredentials: allowCredentials,
              requestOrigin: origin,
              expectAllowed: true,
            ),
          );
        }

        final allowedSansWildcard = allowed;

        final hasAllowable = allowedSansWildcard.isNotEmpty;

        return Gen.boolean().flatMap((shouldAllow) {
          if (shouldAllow && hasAllowable) {
            return Gen.oneOf(allowedSansWildcard).map(
              (origin) => (
                allowedOrigins: allowedSansWildcard,
                allowCredentials: allowCredentials,
                requestOrigin: origin,
                expectAllowed: true,
              ),
            );
          }

          final disallowedCandidates = allCandidates
              .where((origin) => !allowedSansWildcard.contains(origin))
              .toList();

          return Gen.oneOf(disallowedCandidates).map(
            (origin) => (
              allowedOrigins: allowedSansWildcard,
              allowCredentials: allowCredentials,
              requestOrigin: origin,
              expectAllowed: false,
            ),
          );
        });
      });
    });
  });
}
