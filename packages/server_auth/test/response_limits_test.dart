import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

String _signedToken() {
  final key = JsonWebKey.fromJson({
    'kty': 'oct',
    'k': base64UrlEncode(utf8.encode('test-secret')),
  });
  return (JsonWebSignatureBuilder()
        ..jsonContent = <String, dynamic>{'sub': 'user-1'}
        ..addRecipient(key, algorithm: 'HS256'))
      .build()
      .toCompactSerialization();
}

JwtVerifier _jwksVerifier(http.Client client) {
  return JwtVerifier(
    options: JwtOptions(
      jwksUri: Uri.parse('https://auth.example/jwks'),
      algorithms: const ['HS256'],
    ),
    httpClient: client,
  );
}

void main() {
  test('OAuth token responses are bounded before JSON/form parsing', () async {
    final client = OAuth2Client(
      tokenEndpoint: Uri.parse('https://auth.example/token'),
      httpClient: MockClient(
        (_) async => http.Response('x' * (1024 * 1024 + 1), 200),
      ),
    );

    await expectLater(
      client.exchangeAuthorizationCode(
        code: 'code',
        redirectUri: Uri.parse('https://app.example/callback'),
      ),
      throwsA(isA<OAuth2Exception>()),
    );
  });

  test('JWKS responses are bounded before key parsing', () async {
    final verifier = _jwksVerifier(
      MockClient((_) async => http.Response('x' * (1024 * 1024 + 1), 200)),
    );

    await expectLater(
      verifier.verifyToken(_signedToken()),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          equals('jwks_response_too_large'),
        ),
      ),
    );
  });

  test('JWKS key sets are bounded by key count', () async {
    final keySet = <String, dynamic>{
      'keys': List<Map<String, String>>.generate(
        129,
        (index) => <String, String>{
          'kty': 'oct',
          'kid': 'key-$index',
          'k': base64UrlEncode(utf8.encode('test-secret')),
        },
      ),
    };
    final verifier = _jwksVerifier(
      MockClient((_) async => http.Response(jsonEncode(keySet), 200)),
    );

    await expectLater(
      verifier.verifyToken(_signedToken()),
      throwsA(
        isA<JwtAuthException>().having(
          (error) => error.message,
          'message',
          equals('jwks_too_many_keys'),
        ),
      ),
    );
  });
}
