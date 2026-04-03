import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthOAuthValidatedCallback supports typed handlers', () async {
    var seen = false;
    Future<void> callback(
      OAuthIntrospectionResult result,
      String context,
    ) async {
      seen = result.active && context == 'ctx';
    }

    final AuthOAuthValidatedCallback<String> typed = callback;

    await typed(
      OAuthIntrospectionResult(active: true, raw: const {'active': true}),
      'ctx',
    );
    expect(seen, isTrue);
  });

  test('auth flow exception exposes code', () {
    final exception = AuthFlowException('invalid_state');
    expect(exception.code, equals('invalid_state'));
    expect(exception.toString(), equals('AuthFlowException(invalid_state)'));
  });

  test('oauth context attributes remain stable', () {
    expect(oauthTokenAttribute, equals('auth.oauth.access_token'));
    expect(oauthClaimsAttribute, equals('auth.oauth.claims'));
    expect(oauthScopeAttribute, equals('auth.oauth.scope'));
  });

  test(
    'materializeOAuthIntrospectionOptions handles disabled and null endpoint',
    () {
      expect(
        materializeOAuthIntrospectionOptions(
          enabled: false,
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        isNull,
      );
      expect(
        materializeOAuthIntrospectionOptions(enabled: true, endpoint: null),
        isNull,
      );
    },
  );

  test(
    'materializeOAuthIntrospectionOptions normalizes optional string fields',
    () {
      final options = materializeOAuthIntrospectionOptions(
        enabled: true,
        endpoint: Uri.parse('https://auth.test/introspect'),
        clientId: '  ',
        clientSecret: 'secret',
        tokenTypeHint: ' access_token ',
      );

      expect(options, isNotNull);
      expect(options!.clientId, isNull);
      expect(options.clientSecret, equals('secret'));
      expect(options.tokenTypeHint, equals('access_token'));
    },
  );

  test('writeOAuthValidationAttributes writes canonical attribute keys', () {
    final validation = OAuthBearerValidationResult(
      token: 'access-token',
      result: OAuthIntrospectionResult(
        active: true,
        raw: const {'active': true, 'scope': 'read:orders'},
      ),
    );

    final attributes = <String, Object?>{};
    writeOAuthValidationAttributes(
      validation,
      setAttribute: (key, value) => attributes[key] = value,
    );

    expect(attributes[oauthTokenAttribute], equals('access-token'));
    expect(attributes[oauthClaimsAttribute], equals(validation.result.raw));
    expect(attributes[oauthScopeAttribute], equals('read:orders'));
  });

  test('oauthTokenExpiryFromSeconds resolves nullable expirations', () {
    final now = DateTime.utc(2026, 2, 24, 12);
    expect(oauthTokenExpiryFromSeconds(null, now: now), isNull);
    expect(
      oauthTokenExpiryFromSeconds(60, now: now),
      equals(now.add(const Duration(seconds: 60))),
    );
  });

  test(
    'validateOAuthBearerAuthorization rejects missing bearer token',
    () async {
      final introspector = OAuth2TokenIntrospector(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          fail('introspection should not run when token is missing');
        }),
      );

      await expectLater(
        validateOAuthBearerAuthorization(
          authorizationHeader: null,
          introspector: introspector,
        ),
        throwsA(
          isA<OAuth2Exception>().having(
            (error) => error.message,
            'message',
            'missing token',
          ),
        ),
      );
    },
  );

  test(
    'validateOAuthBearerAuthorization validates token and returns result',
    () async {
      final introspector = OAuth2TokenIntrospector(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          expect(request.bodyFields['token'], equals('valid-token'));
          return http.Response(
            jsonEncode({'active': true, 'sub': 'user-1'}),
            200,
          );
        }),
      );

      final validation = await validateOAuthBearerAuthorization(
        authorizationHeader: 'Bearer valid-token',
        introspector: introspector,
      );
      expect(validation.token, equals('valid-token'));
      expect(validation.result.subject, equals('user-1'));
    },
  );

  test(
    'validateOAuthBearerAuthorizationAndWriteAttributes writes attributes and invokes callback',
    () async {
      final introspector = OAuth2TokenIntrospector(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          expect(request.bodyFields['token'], equals('valid-token'));
          return http.Response(
            jsonEncode({'active': true, 'sub': 'user-1', 'scope': 'read'}),
            200,
          );
        }),
      );

      final attributes = <String, Object?>{};
      String? callbackContext;
      final validation =
          await validateOAuthBearerAuthorizationAndWriteAttributes<String>(
            authorizationHeader: 'Bearer valid-token',
            introspector: introspector,
            setAttribute: (key, value) => attributes[key] = value,
            context: 'ctx',
            onValidated: (result, ctx) {
              callbackContext = ctx;
              expect(result.subject, equals('user-1'));
            },
          );

      expect(validation.token, equals('valid-token'));
      expect(attributes[oauthTokenAttribute], equals('valid-token'));
      expect(attributes[oauthClaimsAttribute], equals(validation.result.raw));
      expect(attributes[oauthScopeAttribute], equals('read'));
      expect(callbackContext, equals('ctx'));
    },
  );

  test('OAuth2TokenIntrospector caches introspection responses', () async {
    var requestCount = 0;
    final introspector = OAuth2TokenIntrospector(
      OAuthIntrospectionOptions(
        endpoint: Uri.parse('https://auth.test/introspect'),
        cacheTtl: const Duration(minutes: 5),
      ),
      httpClient: MockClient((request) async {
        requestCount += 1;
        expect(request.bodyFields['token'], equals('cached-token'));
        return http.Response(
          jsonEncode({'active': true, 'sub': 'user-1'}),
          200,
        );
      }),
    );

    final first = await introspector.introspect('cached-token');
    final second = await introspector.introspect('cached-token');

    expect(first.subject, equals('user-1'));
    expect(second.subject, equals('user-1'));
    expect(requestCount, equals(1));
  });

  test(
    'OAuth2TokenIntrospector forwards credentials and extra parameters',
    () async {
      late http.Request captured;
      final introspector = OAuth2TokenIntrospector(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          clientId: 'client-id',
          clientSecret: 'client-secret',
          tokenTypeHint: 'access_token',
          additionalParameters: const {'audience': 'api'},
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'active': true}), 200);
        }),
      );

      await introspector.validate('token');

      final expected = base64Encode(utf8.encode('client-id:client-secret'));
      expect(
        captured.headers[HttpHeaders.authorizationHeader],
        equals('Basic $expected'),
      );
      expect(captured.bodyFields['token_type_hint'], equals('access_token'));
      expect(captured.bodyFields['audience'], equals('api'));
    },
  );

  test('OAuth2TokenIntrospector rejects inactive tokens', () async {
    final introspector = OAuth2TokenIntrospector(
      OAuthIntrospectionOptions(
        endpoint: Uri.parse('https://auth.test/introspect'),
      ),
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'active': false}), 200);
      }),
    );

    await expectLater(
      introspector.validate('inactive-token'),
      throwsA(
        isA<OAuth2Exception>().having(
          (error) => error.message,
          'message',
          'token inactive',
        ),
      ),
    );
  });

  test(
    'OAuth2TokenIntrospector rejects tokens outside temporal bounds',
    () async {
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      var call = 0;
      final introspector = OAuth2TokenIntrospector(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          cacheTtl: Duration.zero,
          clockSkew: Duration.zero,
        ),
        httpClient: MockClient((request) async {
          call += 1;
          if (call == 1) {
            return http.Response(
              jsonEncode({'active': true, 'exp': nowSeconds - 60}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'active': true, 'nbf': nowSeconds + 60}),
            200,
          );
        }),
      );

      await expectLater(
        introspector.validate('expired-token'),
        throwsA(
          isA<OAuth2Exception>().having(
            (error) => error.message,
            'message',
            'token expired',
          ),
        ),
      );
      await expectLater(
        introspector.validate('future-token'),
        throwsA(
          isA<OAuth2Exception>().having(
            (error) => error.message,
            'message',
            'token not yet valid',
          ),
        ),
      );
    },
  );
}
