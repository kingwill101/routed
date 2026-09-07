import 'dart:io';

import 'package:routed_architecture_tenant_app/app.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

String _cookie(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  test(
    'tenant authorization prevents cross-organization data access',
    () async {
      final engine = await createEngine();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final anonymous = await client.get(
        '/api/projects',
        headers: <String, List<String>>{
          'X-Organization-Id': <String>[acmeId],
        },
      );
      anonymous.assertStatus(HttpStatus.unauthorized);

      final login = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'alice@example.com',
          'password': 'password123',
        },
      );
      login.assertStatus(HttpStatus.ok);
      final session = login.cookie('tenant_example_session');
      expect(session, isNotNull);
      final headers = <String, List<String>>{
        HttpHeaders.cookieHeader: <String>[_cookie(session!)],
      };

      final acme = await client.get(
        '/api/projects',
        headers: <String, List<String>>{
          ...headers,
          'X-Organization-Id': <String>[acmeId],
        },
      );
      acme.assertStatus(HttpStatus.ok);
      expect(acme.json()['data'], hasLength(1));
      expect(acme.json()['data'].first['tenant_id'], acmeId);

      final beta = await client.get(
        '/api/projects',
        headers: <String, List<String>>{
          ...headers,
          'X-Organization-Id': <String>[betaId],
        },
      );
      beta.assertStatus(HttpStatus.forbidden);
      expect(beta.json()['error'], 'organization_forbidden');
    },
  );
}
