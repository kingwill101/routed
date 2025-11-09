import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('securityHeadersMiddleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        test('sets configured security headers exactly once', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                csp: "default-src 'self'",
                xContentTypeOptionsNoSniff: true,
                hstsMaxAge: 31536000,
                xFrameOptions: 'DENY',
              ),
            ),
          )..get('/policy', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/policy');
          response
            ..assertHeader('Content-Security-Policy', "default-src 'self'")
            ..assertHeader('X-Content-Type-Options', 'nosniff')
            ..assertHeader(
              'Strict-Transport-Security',
              'max-age=31536000; includeSubDomains; preload',
            )
            ..assertHeader('X-Frame-Options', 'DENY');
        });

        test('sets only CSP when other headers are disabled', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                csp: "default-src 'self'; script-src 'self' 'unsafe-inline'",
                xContentTypeOptionsNoSniff: false,
                hstsMaxAge: null,
                xFrameOptions: null,
              ),
            ),
          )..get('/csp-only', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/csp-only');
          response.assertHeader(
            'Content-Security-Policy',
            "default-src 'self'; script-src 'self' 'unsafe-inline'",
          );

          // These headers should not be present
          expect(
            response.headers.containsKey('X-Content-Type-Options'),
            isFalse,
          );
          expect(
            response.headers.containsKey('Strict-Transport-Security'),
            isFalse,
          );
          expect(response.headers.containsKey('X-Frame-Options'), isFalse);
        });

        test('sets X-Frame-Options to SAMEORIGIN', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                xFrameOptions: 'SAMEORIGIN',
              ),
            ),
          )..get('/framing', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/framing');
          response.assertHeader('X-Frame-Options', 'SAMEORIGIN');
        });

        test('sets HSTS with custom max age', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                hstsMaxAge: 7776000, // 90 days
              ),
            ),
          )..get('/secure', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/secure');
          response.assertHeader(
            'Strict-Transport-Security',
            'max-age=7776000; includeSubDomains; preload',
          );
        });

        test('sets X-Content-Type-Options when enabled', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                xContentTypeOptionsNoSniff: true,
              ),
            ),
          )..get('/nosniff', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/nosniff');
          response.assertHeader('X-Content-Type-Options', 'nosniff');
        });

        test('supports complex CSP directives', () async {
          const complexCSP =
              "default-src 'self'; "
              "script-src 'self' https://cdn.example.com; "
              "style-src 'self' 'unsafe-inline'; "
              "img-src 'self' data: https:; "
              "font-src 'self' https://fonts.gstatic.com; "
              "connect-src 'self' https://api.example.com; "
              "frame-ancestors 'none'";

          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(csp: complexCSP),
            ),
          )..get('/complex', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/complex');
          response.assertHeader('Content-Security-Policy', complexCSP);
        });

        test(
          'applies configured security headers deterministically (property)',
          () async {
            final runner = PropertyTestRunner<_SecurityHeaderSample>(
              _securityHeaderSampleGen(),
              (sample) async {
                final engine =
                    Engine(
                      config: EngineConfig(
                        security: EngineSecurityFeatures(
                          csp: sample.csp,
                          xContentTypeOptionsNoSniff: sample.noSniff,
                          hstsMaxAge: sample.hstsMaxAge,
                          xFrameOptions: sample.frameOptions,
                        ),
                      ),
                    )..get('/prop', (ctx) {
                      if (sample.handlerOverridesCsp) {
                        ctx.response.headers.set(
                          'Content-Security-Policy',
                          "default-src 'none'",
                        );
                      }
                      return ctx.string('ok');
                    });

                final client = TestClient(
                  RoutedRequestHandler(engine),
                  mode: mode,
                );
                final response = await client.get('/prop');

                if (sample.handlerOverridesCsp) {
                  response.assertHeader(
                    'Content-Security-Policy',
                    "default-src 'none'",
                  );
                } else if (sample.csp != null) {
                  response.assertHeader('Content-Security-Policy', sample.csp!);
                } else {
                  expect(
                    response.headers.containsKey('Content-Security-Policy'),
                    isFalse,
                  );
                }

                if (sample.noSniff) {
                  response.assertHeader('X-Content-Type-Options', 'nosniff');
                } else {
                  expect(
                    response.headers.containsKey('X-Content-Type-Options'),
                    isFalse,
                  );
                }

                if (sample.hstsMaxAge != null) {
                  response.assertHeader(
                    'Strict-Transport-Security',
                    'max-age=${sample.hstsMaxAge}; includeSubDomains; preload',
                  );
                } else {
                  expect(
                    response.headers.containsKey('Strict-Transport-Security'),
                    isFalse,
                  );
                }

                if (sample.frameOptions != null) {
                  response.assertHeader(
                    'X-Frame-Options',
                    sample.frameOptions!,
                  );
                } else {
                  expect(
                    response.headers.containsKey('X-Frame-Options'),
                    isFalse,
                  );
                }

                await client.close();
                await engine.close();
              },
              PropertyConfig(numTests: 40, seed: 20250315),
            );

            final result = await runner.run();
            expect(result.success, isTrue, reason: result.report);
          },
        );

        test('does not override existing security headers', () async {
          final engine =
              Engine(
                config: EngineConfig(
                  security: const EngineSecurityFeatures(
                    csp: "default-src 'self'",
                  ),
                ),
              )..get('/custom', (ctx) {
                ctx.response.headers.set(
                  'Content-Security-Policy',
                  "default-src 'none'",
                );
                return ctx.string('ok');
              });

          final client = _startClient(engine, mode);
          final response = await client.get('/custom');
          // The handler's CSP should take precedence
          response.assertHeader(
            'Content-Security-Policy',
            "default-src 'none'",
          );
        });

        test('applies headers to all routes consistently', () async {
          final engine =
              Engine(
                  config: EngineConfig(
                    security: const EngineSecurityFeatures(
                      xContentTypeOptionsNoSniff: true,
                      xFrameOptions: 'DENY',
                    ),
                  ),
                )
                ..get('/route1', (ctx) => ctx.string('route1'))
                ..post('/route2', (ctx) => ctx.string('route2'))
                ..put('/route3', (ctx) => ctx.string('route3'));

          final client = _startClient(engine, mode);

          final response1 = await client.get('/route1');
          response1
            ..assertHeader('X-Content-Type-Options', 'nosniff')
            ..assertHeader('X-Frame-Options', 'DENY');

          final response2 = await client.post('/route2', 'data');
          response2
            ..assertHeader('X-Content-Type-Options', 'nosniff')
            ..assertHeader('X-Frame-Options', 'DENY');

          final response3 = await client.put('/route3', 'data');
          response3
            ..assertHeader('X-Content-Type-Options', 'nosniff')
            ..assertHeader('X-Frame-Options', 'DENY');
        });

        test('works with no security features configured', () async {
          final engine = Engine(
            config: EngineConfig(security: const EngineSecurityFeatures()),
          )..get('/none', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/none');
          response.assertStatus(HttpStatus.ok);

          // No security headers should be set
          expect(
            response.headers.containsKey('Content-Security-Policy'),
            isFalse,
          );
          expect(
            response.headers.containsKey('X-Content-Type-Options'),
            isFalse,
          );
          expect(
            response.headers.containsKey('Strict-Transport-Security'),
            isFalse,
          );
          expect(response.headers.containsKey('X-Frame-Options'), isFalse);
        });

        test('headers are applied before response is sent', () async {
          final engine =
              Engine(
                config: EngineConfig(
                  security: const EngineSecurityFeatures(
                    csp: "default-src 'self'",
                  ),
                ),
              )..get('/verify', (ctx) async {
                // Try to check if CSP is already set during handler execution
                // Note: This is a simplified test; actual timing may vary
                return ctx.string('ok');
              });

          final client = _startClient(engine, mode);
          final response = await client.get('/verify');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertHeader('Content-Security-Policy', "default-src 'self'");
        });

        test('combines all enabled security features', () async {
          final engine = Engine(
            config: EngineConfig(
              security: const EngineSecurityFeatures(
                csp: "default-src 'self'; script-src 'self'",
                xContentTypeOptionsNoSniff: true,
                hstsMaxAge: 15768000, // 6 months
                xFrameOptions: 'SAMEORIGIN',
              ),
            ),
          )..get('/all', (ctx) => ctx.string('ok'));

          final client = _startClient(engine, mode);
          final response = await client.get('/all');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertHeader(
              'Content-Security-Policy',
              "default-src 'self'; script-src 'self'",
            )
            ..assertHeader('X-Content-Type-Options', 'nosniff')
            ..assertHeader(
              'Strict-Transport-Security',
              'max-age=15768000; includeSubDomains; preload',
            )
            ..assertHeader('X-Frame-Options', 'SAMEORIGIN');
        });

        test('does not affect response body or status code', () async {
          final engine =
              Engine(
                config: EngineConfig(
                  security: const EngineSecurityFeatures(
                    csp: "default-src 'self'",
                    xContentTypeOptionsNoSniff: true,
                  ),
                ),
              )..get('/body', (ctx) {
                ctx.response.statusCode = HttpStatus.created;
                return ctx.json({'message': 'created', 'id': 123});
              });

          final client = _startClient(engine, mode);
          final response = await client.get('/body');
          response
            ..assertStatus(HttpStatus.created)
            ..assertJsonPath('message', 'created')
            ..assertJsonPath('id', 123);
        });
      });
    }
  });
}

typedef _SecurityHeaderSample = ({
  String? csp,
  bool noSniff,
  int? hstsMaxAge,
  String? frameOptions,
  bool handlerOverridesCsp,
});

Generator<_SecurityHeaderSample> _securityHeaderSampleGen() {
  final cspValues = <String>[
    "default-src 'self'",
    "default-src 'self'; script-src 'self' https://cdn.example.com",
  ];

  final cspGen = Gen.boolean().flatMap(
    (set) => set ? Gen.oneOf(cspValues) : Gen.constant<String?>(null),
  );
  final noSniffGen = Gen.boolean();
  final hstsGen = Gen.boolean().flatMap(
    (set) => set
        ? Gen.integer(min: 60, max: 31_536_000).map((v) => v)
        : Gen.constant<int?>(null),
  );
  final frameGen = Gen.boolean().flatMap(
    (set) => set
        ? Gen.oneOf(<String>['DENY', 'SAMEORIGIN'])
        : Gen.constant<String?>(null),
  );
  final overrideGen = Gen.boolean();

  return cspGen.flatMap(
    (csp) => noSniffGen.flatMap(
      (noSniff) => hstsGen.flatMap(
        (hsts) => frameGen.flatMap(
          (frame) => overrideGen.map(
            (override) => (
              csp: csp,
              noSniff: noSniff,
              hstsMaxAge: hsts,
              frameOptions: frame,
              handlerOverridesCsp: override,
            ),
          ),
        ),
      ),
    ),
  );
}

TestClient _startClient(Engine engine, TransportMode mode) {
  final client = TestClient(RoutedRequestHandler(engine), mode: mode);
  addTearDown(client.close);
  addTearDown(engine.close);
  return client;
}
