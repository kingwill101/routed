import 'dart:convert';

import 'package:jose/jose.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

typedef ConfigMap = Map<String, Object?>;

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

        final engine = Engine();
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
      final engine = Engine()
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
    });

    test('custom validator can reject tokens', () async {
      final now = DateTime.now();
      final invalidToken = _buildToken(
        _claims(now: now, scope: 'write:orders'),
      );

      final engine = Engine()
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
                throw JwtAuthException('scope');
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
    });

    test('rejects expired tokens', () async {
      final now = DateTime.now();
      final expiredToken = _buildToken(
        _claims(now: now, expiresIn: const Duration(minutes: -2)),
      );

      final engine = Engine()
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

      final engine = Engine()
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

      final engine = Engine()
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
    Engine buildEngine({required ConfigMap authConfig}) {
      return Engine(
        configItems: {
          'http': {
            'features': {
              'auth': {'enabled': true},
            },
          },
          'auth': authConfig,
        },
      );
    }

    test('valid token passes with provider-configured middleware', () async {
      final now = DateTime.now();
      final token = _buildToken(_claims(now: now));

      final engine = buildEngine(
        authConfig: {
          'jwt': {
            'enabled': true,
            'issuer': 'https://issuer.test',
            'audience': ['api'],
            'keys': [_testJwk],
            'algorithms': ['HS256'],
          },
        },
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
  });
}
