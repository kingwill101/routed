import 'dart:convert';

import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';
import 'package:routed_cloudflare_auth_example/app.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

const _origin = 'https://example.test';
const _sessionKey =
    'base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';

void main() {
  late SqliteAuthStore store;
  late Engine engine;
  late TestClient client;

  setUp(() async {
    store = await SqliteAuthStore.openInMemory();
    engine = await buildAuthEngine(
      store: store,
      origin: Uri.parse(_origin),
      sessionKey: _sessionKey,
    );
    client = TestClient.inMemory(RoutedRequestHandler(engine));
  });

  tearDown(() async {
    await client.close();
    await engine.close();
    store.close();
  });

  test('boots the documented health and provider routes', () async {
    final health = await client.getJson('/health');
    health.assertStatus(HttpStatus.ok).assertJson((json) {
      json.where('ok', true).where('store', 'cloudflare_d1');
    });

    final providers = await client.getJson('/auth/providers');
    providers.assertStatus(HttpStatus.ok).assertJson((json) {
      json.has('providers');
    });
  });

  test(
    'registers and authenticates a user through the session cookie',
    () async {
      final unauthenticated = await client.get('/account');
      unauthenticated.assertStatus(HttpStatus.unauthorized);

      final csrf = await client.get('/auth/csrf');
      csrf.assertStatus(HttpStatus.ok);
      final csrfToken = (csrf.json() as Map<String, dynamic>)['csrfToken'];
      expect(csrfToken, isA<String>());

      final registered = await client.postJson(
        '/auth/register/credentials',
        <String, Object?>{
          'email': 'worker@example.test',
          'password': 'a deliberately long password',
          '_csrf': csrfToken,
        },
        headers: <String, List<String>>{
          'origin': [_origin],
        },
      );
      registered.assertStatus(HttpStatus.ok);
      expect(registered.json()['user']['email'], 'worker@example.test');

      final account = await client.getJson('/account');
      account.assertStatus(HttpStatus.ok).assertJson((json) {
        json.where('authenticated', true).where('email', 'worker@example.test');
      });

      final session = await client.get('/auth/session');
      session.assertStatus(HttpStatus.ok);
      expect(jsonDecode(session.body)['user']['email'], 'worker@example.test');
    },
  );
}
