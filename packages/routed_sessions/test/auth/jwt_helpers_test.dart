import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';
import 'package:routed/auth.dart';
import 'package:test/test.dart';

const _sharedSecret = 'secret-test-key';

Map<String, dynamic> get _testJwk => <String, dynamic>{
  'kty': 'oct',
  'kid': 'test-key',
  'alg': 'HS256',
  'k': base64UrlEncode(utf8.encode(_sharedSecret)).replaceAll('=', ''),
};

String _buildToken(
  Map<String, dynamic> claims, {
  String secret = _sharedSecret,
}) {
  final key = JsonWebKey.fromJson({
    'kty': 'oct',
    'kid': 'test-key',
    'alg': 'HS256',
    'k': base64UrlEncode(utf8.encode(secret)).replaceAll('=', ''),
  });
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = claims
    ..setProtectedHeader('alg', 'HS256')
    ..setProtectedHeader('typ', 'JWT')
    ..addRecipient(key, algorithm: 'HS256');
  return builder.build().toCompactSerialization();
}

Map<String, dynamic> _claims({
  required DateTime now,
  Duration expiresIn = const Duration(minutes: 5),
  Duration notBeforeOffset = Duration.zero,
  String issuer = 'routed',
  List<String> audience = const ['demo'],
}) {
  return <String, dynamic>{
    'sub': 'user-1',
    'iss': issuer,
    'aud': audience,
    'exp': _secondsSinceEpoch(now.add(expiresIn)),
    'nbf': _secondsSinceEpoch(now.add(notBeforeOffset)),
    'iat': _secondsSinceEpoch(now),
  };
}

int _secondsSinceEpoch(DateTime time) =>
    time.toUtc().millisecondsSinceEpoch ~/ 1000;

void main() {
  test('JwtIssuer and JwtVerifier roundtrip', () async {
    const options = JwtSessionOptions(
      secret: 'super-secret',
      issuer: 'routed',
      audience: ['demo'],
    );
    final issuer = JwtIssuer(options);
    final token = issuer.issue({
      'sub': 'user-1',
      'roles': ['admin'],
    });

    final verifier = JwtVerifier(options: options.toVerifierOptions());
    final payload = await verifier.verifyToken(token);

    expect(payload.subject, equals('user-1'));
    expect(payload.claims['roles'], isA<List<dynamic>>());
    expect((payload.claims['roles'] as List).first, equals('admin'));
  });

  test('JwtVerifier rejects invalid token format', () async {
    final verifier = JwtVerifier(
      options: JwtOptions(inlineKeys: [_testJwk], algorithms: const ['HS256']),
    );

    expect(
      verifier.verifyToken('not-a-token'),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'invalid_format',
        ),
      ),
    );
  });

  test('JwtVerifier rejects tokens when no keys configured', () async {
    final token = _buildToken(_claims(now: DateTime.now()));
    final verifier = JwtVerifier(
      options: const JwtOptions(algorithms: ['HS256']),
    );

    expect(
      verifier.verifyToken(token),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'no_keys_configured',
        ),
      ),
    );
  });

  test('JwtVerifier reports JWKS fetch failures', () async {
    final token = _buildToken(_claims(now: DateTime.now()));
    final verifier = JwtVerifier(
      options: JwtOptions(
        jwksUri: Uri.parse('https://auth.test/jwks'),
        algorithms: const ['HS256'],
      ),
      httpClient: MockClient((request) async {
        return http.Response('fail', 500);
      }),
    );

    expect(
      verifier.verifyToken(token),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'jwks_fetch_failed',
        ),
      ),
    );
  });

  test('JwtVerifier reports malformed JWKS payloads', () async {
    final token = _buildToken(_claims(now: DateTime.now()));
    final verifier = JwtVerifier(
      options: JwtOptions(
        jwksUri: Uri.parse('https://auth.test/jwks'),
        algorithms: const ['HS256'],
      ),
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'invalid': true}), 200);
      }),
    );

    expect(
      verifier.verifyToken(token),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'jwks_missing_keys',
        ),
      ),
    );
  });

  test('JwtVerifier caches JWKS responses', () async {
    final token = _buildToken(_claims(now: DateTime.now()));
    var requestCount = 0;
    final verifier = JwtVerifier(
      options: JwtOptions(
        jwksUri: Uri.parse('https://auth.test/jwks'),
        algorithms: const ['HS256'],
        jwksCacheTtl: const Duration(minutes: 10),
      ),
      httpClient: MockClient((request) async {
        requestCount += 1;
        return http.Response(
          jsonEncode({
            'keys': [_testJwk],
          }),
          200,
        );
      }),
    );

    await verifier.verifyToken(token);
    await verifier.verifyToken(token);

    expect(requestCount, equals(1));
  });

  test('JwtVerifier rejects tokens with invalid signature', () async {
    final token = _buildToken(
      _claims(now: DateTime.now()),
      secret: 'different-secret',
    );
    final verifier = JwtVerifier(
      options: JwtOptions(inlineKeys: [_testJwk], algorithms: const ['HS256']),
    );

    expect(
      verifier.verifyToken(token),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'signature_verification_failed',
        ),
      ),
    );
  });

  test('JwtVerifier validates issuer, audience, and required claims', () async {
    final now = DateTime.now();
    final issuerMismatch = _buildToken(_claims(now: now, issuer: 'other'));
    final verifier = JwtVerifier(
      options: JwtOptions(
        issuer: 'routed',
        audience: const ['demo'],
        requiredClaims: const ['role'],
        inlineKeys: [_testJwk],
        algorithms: const ['HS256'],
      ),
    );

    await expectLater(
      verifier.verifyToken(issuerMismatch),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'issuer_mismatch',
        ),
      ),
    );

    final audienceMismatch = _buildToken(
      _claims(now: now, audience: const ['other']),
    );
    await expectLater(
      verifier.verifyToken(audienceMismatch),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'audience_mismatch',
        ),
      ),
    );

    final missingClaim = _buildToken(_claims(now: now));
    await expectLater(
      verifier.verifyToken(missingClaim),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          'missing_claim_role',
        ),
      ),
    );
  });

  test('JwtOptions copyWith applies overrides', () {
    const options = JwtOptions(
      enabled: true,
      issuer: 'routed',
      audience: ['demo'],
      requiredClaims: ['role'],
      jwksUri: null,
      inlineKeys: [],
      algorithms: ['HS256'],
      clockSkew: Duration(seconds: 15),
      jwksCacheTtl: Duration(minutes: 1),
      header: 'Authorization',
      bearerPrefix: 'Bearer ',
      cookieName: 'auth',
    );

    final updated = options.copyWith(
      enabled: false,
      issuer: 'custom',
      audience: ['api'],
      requiredClaims: ['scope'],
      jwksUri: Uri.parse('https://auth.test/jwks'),
      inlineKeys: [_testJwk],
      algorithms: ['RS256'],
      clockSkew: const Duration(seconds: 5),
      jwksCacheTtl: const Duration(minutes: 5),
      header: 'X-Auth',
      bearerPrefix: 'Token ',
      cookieName: 'cookie',
    );

    expect(updated.enabled, isFalse);
    expect(updated.issuer, equals('custom'));
    expect(updated.audience, equals(['api']));
    expect(updated.requiredClaims, equals(['scope']));
    expect(updated.jwksUri.toString(), equals('https://auth.test/jwks'));
    expect(updated.inlineKeys, isNotEmpty);
    expect(updated.algorithms, equals(['RS256']));
    expect(updated.clockSkew, equals(const Duration(seconds: 5)));
    expect(updated.jwksCacheTtl, equals(const Duration(minutes: 5)));
    expect(updated.header, equals('X-Auth'));
    expect(updated.bearerPrefix, equals('Token '));
    expect(updated.cookieName, equals('cookie'));
  });
}
