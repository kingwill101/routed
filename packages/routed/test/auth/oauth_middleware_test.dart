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

    test('rejects requests missing authorization headers', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          return http.Response(json.encode({'active': true}), 200);
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

      final res = await client.get('/secure');
      expect(res.statusCode, equals(401));
    });

    test('rejects empty bearer tokens', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          return http.Response(json.encode({'active': true}), 200);
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
          'Authorization': ['Bearer '],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('rejects non-bearer authorization schemes', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          return http.Response(json.encode({'active': true}), 200);
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
          'Authorization': ['Basic abc'],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('applies client credentials and token type hints', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          clientId: 'client-id',
          clientSecret: 'client-secret',
          tokenTypeHint: 'access_token',
          additionalParameters: const {'audience': 'api'},
        ),
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], isNotNull);
          expect(request.bodyFields['token_type_hint'], equals('access_token'));
          expect(request.bodyFields['audience'], equals('api'));
          return http.Response(json.encode({'active': true}), 200);
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
          'Authorization': ['Bearer token'],
        },
      );
      res.assertStatus(200);
    });

    test('handles introspection errors gracefully', () async {
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
        ),
        httpClient: MockClient((request) async {
          return http.Response('nope', 500);
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
          'Authorization': ['Bearer bad'],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('invokes onValidated callback and caches responses', () async {
      var requestCount = 0;
      var validated = false;
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          cacheTtl: const Duration(minutes: 5),
        ),
        onValidated: (result, ctx) {
          validated = true;
          ctx.request.setAttribute('user', result.subject);
        },
        httpClient: MockClient((request) async {
          requestCount += 1;
          return http.Response(
            json.encode({'active': true, 'sub': 'user-1'}),
            200,
          );
        }),
      );

      final engine = testEngine()
        ..addGlobalMiddleware(middleware)
        ..get('/secure', (ctx) {
          return ctx.json({'user': ctx.request.getAttribute<String>('user')});
        });

      await engine.initialize();

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async => await client.close());

      final first = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer cached'],
        },
      );
      first.assertStatus(200);
      expect(first.json()['user'], equals('user-1'));
      expect(validated, isTrue);

      final second = await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer cached'],
        },
      );
      second.assertStatus(200);
      expect(requestCount, equals(1));
    });

    test('refreshes cached introspection when expired', () async {
      var requestCount = 0;
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          cacheTtl: Duration.zero,
        ),
        httpClient: MockClient((request) async {
          requestCount += 1;
          return http.Response(
            json.encode({'active': true, 'sub': 'user-1'}),
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

      await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer refresh'],
        },
      );
      await client.get(
        '/secure',
        headers: {
          'Authorization': ['Bearer refresh'],
        },
      );

      expect(requestCount, equals(2));
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

    test('rejects expired tokens', () async {
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          clockSkew: Duration.zero,
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            json.encode({
              'active': true,
              'sub': 'user-2',
              'exp': nowSeconds - 120,
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
          'Authorization': ['Bearer expired'],
        },
      );
      expect(res.statusCode, equals(401));
    });

    test('rejects tokens not yet valid', () async {
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final middleware = oauth2Introspection(
        OAuthIntrospectionOptions(
          endpoint: Uri.parse('https://auth.test/introspect'),
          clockSkew: Duration.zero,
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            json.encode({
              'active': true,
              'sub': 'user-2',
              'nbf': nowSeconds + 120,
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
