import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('OAuth2Client', () {
    test('exchanges authorization code', () async {
      late http.Request captured;
      final client = OAuth2Client(
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        clientId: 'client-id',
        clientSecret: 'client-secret',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            json.encode({'access_token': 'abc', 'token_type': 'Bearer'}),
            200,
          );
        }),
      );

      await client.exchangeAuthorizationCode(
        code: 'code123',
        redirectUri: Uri.parse('https://app.test/callback'),
      );

      expect(captured.method, equals('POST'));
      expect(captured.url.toString(), equals('https://auth.test/token'));
      final body = captured.bodyFields;
      expect(body['grant_type'], equals('authorization_code'));
      expect(body['code'], equals('code123'));
      expect(body['client_id'], equals('client-id'));
      expect(
        captured.headers['authorization'],
        equals('Basic ${base64Encode(utf8.encode('client-id:client-secret'))}'),
      );
    });

    test('requests client credentials token', () async {
      late http.Request captured;
      final client = OAuth2Client(
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            json.encode({'access_token': 'abc', 'token_type': 'Bearer'}),
            200,
          );
        }),
        clientId: 'public-client',
      );

      await client.clientCredentials(scope: 'read');

      final body = captured.bodyFields;
      expect(body['grant_type'], equals('client_credentials'));
      expect(body['scope'], equals('read'));
      expect(body['client_id'], equals('public-client'));
    });
  });

  group('oauth2Introspection middleware', () {
    test('allows active tokens', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          cacheTtl: const Duration(minutes: 5),
        ),
        httpClient: MockClient((request) async {
          expect(request.bodyFields['token'], equals('valid-token'));
          return http.Response(
            json.encode({'active': true, 'sub': 'user-1', 'scope': 'read'}),
            200,
          );
        }),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(middleware)
        ..get('/secure', (ctx) {
          final claims = ctx.request.getAttribute<Map<String, dynamic>>(
            oauthClaimsAttribute,
          );
          return ctx.json({'sub': claims?['sub']});
        });

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final res = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer valid-token'],
        },
      );
      res.assertStatus(200);
      expect(res.json()['sub'], equals('user-1'));
    });

    test('rejects inactive tokens', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          return http.Response(json.encode({'active': false}), 200);
        }),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(middleware)
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
          'Authorization': ['Bearer expired'],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('accepts tokens within clock skew tolerance', () async {
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          clockSkew: const Duration(seconds: 45),
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            json.encode({
              'active': true,
              'sub': 'user-2',
              'exp': nowSeconds - 20,
            }),
            200,
          );
        }),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(middleware)
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
          'Authorization': ['Bearer tolerant'],
        },
      );
      res.assertStatus(200);
    });

    test('rejects tokens outside clock skew tolerance', () async {
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          clockSkew: const Duration(seconds: 30),
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            json.encode({
              'active': true,
              'sub': 'user-3',
              'nbf': nowSeconds + 45,
            }),
            200,
          );
        }),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(middleware)
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
          'Authorization': ['Bearer future'],
        },
      );
      expect(res.statusCode, equals(401));
    });
  });
}
