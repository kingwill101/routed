import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

const _sharedSecret = 'secret-test-key';

Map<String, dynamic> get _testJwk => <String, dynamic>{
  'kty': 'oct',
  'kid': 'test-key',
  'alg': 'HS256',
  'k': base64UrlEncode(utf8.encode(_sharedSecret)).replaceAll('=', ''),
};

Map<String, dynamic> _claims({
  required DateTime now,
  Duration expiresIn = const Duration(minutes: 5),
  Duration notBeforeOffset = Duration.zero,
  String scope = 'read:orders',
}) {
  return <String, dynamic>{
    'sub': 'user-123',
    'iss': 'https://issuer.test',
    'aud': ['api'],
    'exp': _secondsSinceEpoch(now.add(expiresIn)),
    'nbf': _secondsSinceEpoch(now.add(notBeforeOffset)),
    'iat': _secondsSinceEpoch(now),
    'scope': scope,
  };
}

int _secondsSinceEpoch(DateTime time) =>
    time.toUtc().millisecondsSinceEpoch ~/ 1000;

String _buildToken(Map<String, dynamic> claims) {
  final key = JsonWebKey.fromJson(_testJwk);
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = claims
    ..setProtectedHeader('alg', 'HS256')
    ..setProtectedHeader('typ', 'JWT')
    ..addRecipient(key, algorithm: 'HS256');
  return builder.build().toCompactSerialization();
}

void main() {
  group('jwtAuthentication helper', () {
    test(
      'accepts valid tokens and exposes claims via request attributes',
      () async {
        final now = DateTime.now();
        final token = _buildToken(_claims(now: now));

        final engine = testEngine();
        engine.addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(
              issuer: 'https://issuer.test',
              audience: const ['api'],
              inlineKeys: [_testJwk],
              algorithms: const ['HS256'],
            ),
            onVerified: (payload, ctx) {
              if (payload.claims['scope'] != 'read:orders') {
                throw JwtAuthException('insufficient_scope');
              }
              ctx.request.setAttribute('user', payload.claims['sub']);
            },
          ),
        );

        engine.get('/me', (ctx) {
          final claims = ctx.request.getAttribute<Map<String, dynamic>>(
            jwtClaimsAttribute,
          );
          final subject = ctx.request.getAttribute<String>('user');
          return ctx.json({'sub': subject, 'scope': claims?['scope']});
        });

        await engine.initialize();

        final client = TestClient(
          RoutedRequestHandler(engine),
          mode: TransportMode.ephemeralServer,
        );
        addTearDown(() async => await client.close());

        final response = await client.get(
          '/me',
          headers: {
            'Authorization': ['Bearer $token'],
          },
        );

        response.assertStatus(200);
        expect(response.json()['sub'], equals('user-123'));
      },
    );

    test('rejects missing tokens', () async {
      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(inlineKeys: [_testJwk], algorithms: const ['HS256']),
          ),
        )
        ..get('/secure', (ctx) => ctx.string('secure'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get('/secure');
      expect(res.statusCode, equals(401));
      expect(
        res.header(HttpHeaders.wwwAuthenticateHeader).first,
        contains('invalid_token'),
      );
      expect(res.body, contains('Unauthorized'));
    });

    test('rejects tokens with unexpected prefix', () async {
      final now = DateTime.now();
      final token = _buildToken(_claims(now: now));

      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(
              inlineKeys: [_testJwk],
              algorithms: const ['HS256'],
              bearerPrefix: 'Token ',
            ),
          ),
        )
        ..get('/secure', (ctx) => ctx.string('secure'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer $token'],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('skips verification when disabled', () async {
      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(const JwtOptions(enabled: false)),
        )
        ..get('/secure', (ctx) => ctx.string('secure'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get('/secure');
      res.assertStatus(200);
    });

    test('custom validator can reject tokens', () async {
      final now = DateTime.now();
      final invalidToken = _buildToken(
        _claims(now: now, scope: 'write:orders'),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(
              issuer: 'https://issuer.test',
              audience: const ['api'],
              inlineKeys: [_testJwk],
              algorithms: const ['HS256'],
            ),
            onVerified: (payload, _) {
              if (!(payload.claims['scope'] as String).contains(
                'read:orders',
              )) {
                throw JwtAuthException('/srv/secrets/jwt-config.json');
              }
            },
          ),
        )
        ..get('/orders', (ctx) => ctx.string('ok'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final failure = await client.get(
        '/orders',
        headers: {
          'Authorization': ['Bearer $invalidToken'],
        },
      );
      expect(failure.statusCode, equals(401));
      final challenge = failure.header(HttpHeaders.wwwAuthenticateHeader).first;
      expect(challenge, contains('error_description="invalid_token"'));
      expect(challenge, isNot(contains('/srv/secrets/jwt-config.json')));
    });

    test('rejects expired tokens', () async {
      final now = DateTime.now();
      final expiredToken = _buildToken(
        _claims(now: now, expiresIn: const Duration(minutes: -2)),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(
              issuer: 'https://issuer.test',
              audience: const ['api'],
              inlineKeys: [_testJwk],
              algorithms: const ['HS256'],
              clockSkew: const Duration(seconds: 0),
            ),
          ),
        )
        ..get('/secure', (ctx) => ctx.string('ok'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer $expiredToken'],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('accepts token within configured clock skew window', () async {
      final now = DateTime.now();
      final token = _buildToken(
        _claims(now: now, expiresIn: const Duration(seconds: -20)),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(
              issuer: 'https://issuer.test',
              audience: const ['api'],
              inlineKeys: [_testJwk],
              algorithms: const ['HS256'],
              clockSkew: const Duration(seconds: 45),
            ),
          ),
        )
        ..get('/secure', (ctx) => ctx.string('ok'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer $token'],
        },
      );
      res.assertStatus(200);
    });

    test('rejects token outside configured clock skew window', () async {
      final now = DateTime.now();
      final token = _buildToken(
        _claims(now: now, notBeforeOffset: const Duration(seconds: 45)),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(
          jwtAuthentication(
            JwtOptions(
              issuer: 'https://issuer.test',
              audience: const ['api'],
              inlineKeys: [_testJwk],
              algorithms: const ['HS256'],
              clockSkew: const Duration(seconds: 30),
            ),
          ),
        )
        ..get('/secure', (ctx) => ctx.string('ok'));

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer $token'],
        },
      );
      expect(res.statusCode, equals(401));
    });
  });

  group('AuthServiceProvider manifest', () {
    Engine buildEngine({required AuthConfig authConfig}) {
      return testEngine(
        providers: [AuthServiceProvider(configuration: authConfig)],
      );
    }

    test('valid token passes with provider-configured middleware', () async {
      final now = DateTime.now();
      final token = _buildToken(_claims(now: now));

      final engine = buildEngine(
        authConfig: AuthConfig.defaults().copyWith(
          jwt: AuthJwtConfig(
            enabled: true,
            issuer: 'https://issuer.test',
            audience: const ['api'],
            requiredClaims: const ['exp'],
            jwksUri: null,
            jwksCacheTtl: const Duration(minutes: 5),
            clockSkew: const Duration(seconds: 60),
            algorithms: const ['HS256'],
            inlineKeys: [_testJwk],
            header: 'Authorization',
            bearerPrefix: 'Bearer ',
          ),
        ),
      );
      addTearDown(() async => await engine.close());

      engine.get('/me', (ctx) {
        final claims = ctx.request.getAttribute<Map<String, dynamic>>(
          jwtClaimsAttribute,
        );
        return ctx.json({'scope': claims?['scope']});
      });

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final response = await client.get(
        '/me',
        headers: {
          'Authorization': ['Bearer $token'],
        },
      );
      response.assertStatus(200);
    });

    test(
      'external JWTs do not require Routed session-version claims',
      () async {
        final token = _buildToken(_claims(now: DateTime.now()));
        final engine = buildEngine(
          authConfig: AuthConfig.defaults().copyWith(
            jwt: AuthJwtConfig(
              enabled: true,
              issuer: 'https://issuer.test',
              audience: const ['api'],
              requiredClaims: const ['exp'],
              jwksUri: null,
              jwksCacheTtl: const Duration(minutes: 5),
              clockSkew: const Duration(seconds: 60),
              algorithms: const ['HS256'],
              inlineKeys: [_testJwk],
              header: 'Authorization',
              bearerPrefix: 'Bearer ',
            ),
          ),
        );
        engine.container.instance<AuthOptions<EngineContext>>(
          AuthOptions<EngineContext>(
            providers: [CredentialsProvider()],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            sessionStrategy: AuthSessionStrategy.jwt,
            jwtOptions: const JwtSessionOptions(secret: 'routed-session-key'),
          ),
        );
        engine.get(
          '/external',
          (ctx) => ctx.json({
            'sub': ctx.request.getAttribute<Map<String, dynamic>>(
              jwtClaimsAttribute,
            )?['sub'],
          }),
          middlewares: [MiddlewareRef.of('routed.auth.jwt')],
        );
        await engine.initialize();
        addTearDown(engine.close);

        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);
        final response = await client.get(
          '/external',
          headers: {
            HttpHeaders.authorizationHeader: ['Bearer $token'],
          },
        );

        response.assertStatus(HttpStatus.ok);
        expect(response.json()['sub'], 'user-123');
      },
    );
  });
}
