import 'dart:io';

import 'package:routed_architecture_tenant_app/app.dart';
import 'package:routed_database/routed_database.dart';
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

  test(
    'durable auth and organization records survive an engine restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'routed-tenant-example-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final databasePath = '${directory.path}/tenant.sqlite';

      final firstEngine = await createEngine(databasePath: databasePath);
      final firstClient = TestClient(RoutedRequestHandler(firstEngine));
      addTearDown(firstClient.close);
      addTearDown(firstEngine.close);
      final firstRows = await firstEngine.container
          .get<DatabaseManager>()
          .database()
          .table('routed_auth_organizations')
          .get();
      expect(firstRows, hasLength(2));
      await firstEngine.container
          .get<DatabaseManager>()
          .database()
          .table('routed_auth_organizations')
          .whereEquals('id', acmeId)
          .update({'name': 'Acme durable mutation', 'slug': 'acme-durable'});
      final firstLogin = await firstClient.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'alice@example.com',
          'password': 'password123',
        },
      );
      firstLogin.assertStatus(HttpStatus.ok);
      final firstSession = firstLogin.cookie('tenant_example_session');
      expect(firstSession, isNotNull);
      await firstEngine.close();
      await firstClient.close();

      final secondEngine = await createEngine(databasePath: databasePath);
      addTearDown(secondEngine.close);
      final secondClient = TestClient(RoutedRequestHandler(secondEngine));
      addTearDown(secondClient.close);
      final resumed = await secondClient.get(
        '/api/me',
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(firstSession!)],
        },
      );
      resumed.assertStatus(HttpStatus.ok);
      expect(resumed.json()['id'], aliceId);
      final login = await secondClient.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'alice@example.com',
          'password': 'password123',
        },
      );
      login.assertStatus(HttpStatus.ok);
      final secondRows = await secondEngine.container
          .get<DatabaseManager>()
          .database()
          .table('routed_auth_organizations')
          .get();
      expect(secondRows, hasLength(2));
      expect(
        secondRows.map((row) => row['slug']),
        containsAll(<String>['acme-durable', 'beta']),
      );
      expect(
        secondRows.singleWhere((row) => row['id'] == acmeId)['name'],
        'Acme durable mutation',
      );
    },
  );
}
