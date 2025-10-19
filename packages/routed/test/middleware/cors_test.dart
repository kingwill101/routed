import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('corsMiddleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        tearDown(() async {
          await client.close();
        });

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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
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

            client = TestClient(RoutedRequestHandler(engine), mode: mode);
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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
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

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
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
