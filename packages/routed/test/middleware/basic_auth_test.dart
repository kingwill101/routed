import 'dart:convert';
import 'package:routed/routed.dart';
import 'package:routed/middlewares.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('basicAuth middleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        setUp(() {
          final engine = testEngine();
          engine.get(
            '/secret',
            (ctx) async {
              final user = ctx.get<String>('user');
              return ctx.json({'user': user});
            },
            middlewares: [
              basicAuth({'admin': 'secret'}),
            ],
          );
          client = TestClient(RoutedRequestHandler(engine), mode: mode);
        });

        tearDown(() async {
          await client.close();
        });

        test('requires credentials and sets WWW-Authenticate header', () async {
          final response = await client.get('/secret');
          response
            ..assertStatus(HttpStatus.unauthorized)
            ..assertHeader('WWW-Authenticate', 'Basic realm="Restricted Area"')
            ..assertJsonPath('error', 'Unauthorized');
        });

        test('rejects invalid credentials and returns same realm', () async {
          final invalid = base64Encode(utf8.encode('admin:wrong-password'));
          final response = await client.get(
            '/secret',
            headers: {
              HttpHeaders.authorizationHeader: ['Basic $invalid'],
            },
          );
          response
            ..assertStatus(HttpStatus.unauthorized)
            ..assertHeader('WWW-Authenticate', 'Basic realm="Restricted Area"')
            ..assertJsonPath('error', 'Unauthorized');
        });

        test('allows valid credentials and exposes username', () async {
          final valid = base64Encode(utf8.encode('admin:secret'));
          final response = await client.get(
            '/secret',
            headers: {
              HttpHeaders.authorizationHeader: ['Basic $valid'],
            },
          );
          response
            ..assertStatus(HttpStatus.ok)
            ..assertJsonPath('user', 'admin');
        });

        test('supports custom realm', () async {
          final customEngine = testEngine();
          customEngine.get(
            '/protected',
            (ctx) => ctx.json({'message': 'ok'}),
            middlewares: [
              basicAuth({'user': 'pass'}, realm: 'Custom Realm'),
            ],
          );
          final customClient = TestClient(
            RoutedRequestHandler(customEngine),
            mode: mode,
          );

          final response = await customClient.get('/protected');
          response
            ..assertStatus(HttpStatus.unauthorized)
            ..assertHeader('WWW-Authenticate', 'Basic realm="Custom Realm"');

          await customClient.close();
        });

        test('handles missing Authorization header', () async {
          final response = await client.get('/secret');
          response.assertStatus(HttpStatus.unauthorized);
        });

        test('handles malformed Authorization header', () async {
          final response = await client.get(
            '/secret',
            headers: {
              HttpHeaders.authorizationHeader: ['Invalid Format'],
            },
          );
          response.assertStatus(HttpStatus.unauthorized);
        });

        test('handles non-Basic auth scheme', () async {
          final response = await client.get(
            '/secret',
            headers: {
              HttpHeaders.authorizationHeader: ['Bearer token123'],
            },
          );
          response.assertStatus(HttpStatus.unauthorized);
        });

        test('supports multiple users', () async {
          final multiUserEngine = testEngine();
          multiUserEngine.get(
            '/data',
            (ctx) async {
              final user = ctx.get<String>('user');
              return ctx.json({'user': user});
            },
            middlewares: [
              basicAuth({
                'alice': 'alice-pass',
                'bob': 'bob-pass',
                'charlie': 'charlie-pass',
              }),
            ],
          );
          final multiUserClient = TestClient(
            RoutedRequestHandler(multiUserEngine),
            mode: mode,
          );

          // Test alice
          final aliceAuth = base64Encode(utf8.encode('alice:alice-pass'));
          final aliceResponse = await multiUserClient.get(
            '/data',
            headers: {
              HttpHeaders.authorizationHeader: ['Basic $aliceAuth'],
            },
          );
          aliceResponse
            ..assertStatus(HttpStatus.ok)
            ..assertJsonPath('user', 'alice');

          // Test bob
          final bobAuth = base64Encode(utf8.encode('bob:bob-pass'));
          final bobResponse = await multiUserClient.get(
            '/data',
            headers: {
              HttpHeaders.authorizationHeader: ['Basic $bobAuth'],
            },
          );
          bobResponse
            ..assertStatus(HttpStatus.ok)
            ..assertJsonPath('user', 'bob');

          await multiUserClient.close();
        });
      });
    }
  });
}
