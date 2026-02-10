import 'dart:convert';

import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

import 'package:openapi_demo/app.dart' as app;

void main() {
  group('API', () {
    late TestClient client;

    setUpAll(() async {
      final engine = await app.createEngine();
      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDownAll(() async {
      await client.close();
    });

    test('lists users', () async {
      final response = await client.get('/api/v1/users');
      response.assertStatus(200).assertJson((json) {
        json.has('data').etc();
      });
    });

    test('gets user by id', () async {
      final response = await client.get('/api/v1/users/1');
      response.assertStatus(200).assertJson((json) {
        json.where('name', 'Ada Lovelace').where('email', 'ada@example.com');
      });
    });

    test('returns 404 for missing user', () async {
      final response = await client.get('/api/v1/users/999');
      response.assertStatus(404);
    });

    test('creates a user', () async {
      final response = await client.post(
        '/api/v1/users',
        jsonEncode({'name': 'Grace Hopper', 'email': 'grace@example.com'}),
        headers: {
          'Content-Type': ['application/json'],
        },
      );
      response.assertStatus(201).assertJson((json) {
        json.where('name', 'Grace Hopper').where('email', 'grace@example.com');
      });
    });
  });

  group('OpenAPI', () {
    late TestClient client;

    setUpAll(() async {
      final engine = await app.createEngine();
      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDownAll(() async {
      await client.close();
    });

    test('serves OpenAPI spec at /openapi.json', () async {
      final response = await client.get('/openapi.json');
      response.assertStatus(200);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['openapi'], '3.1.0');
      expect(body['info']['title'], 'OpenAPI Demo');
      expect(body['info']['version'], '1.0.0');
    });

    test('spec contains documented paths', () async {
      final response = await client.get('/openapi.json');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = body['paths'] as Map<String, dynamic>;

      expect(paths, contains('/api/v1/users'));
      expect(paths, contains('/api/v1/users/{id}'));
    });

    test('spec excludes hidden routes', () async {
      final response = await client.get('/openapi.json');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = body['paths'] as Map<String, dynamic>;

      // The health check is marked hidden, should not appear
      expect(paths, isNot(contains('/api/v1/health')));
    });

    test('spec marks deprecated operations', () async {
      final response = await client.get('/openapi.json');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = body['paths'] as Map<String, dynamic>;

      final usersById = paths['/api/v1/users/{id}'] as Map<String, dynamic>;
      final deleteOp = usersById['delete'] as Map<String, dynamic>;
      expect(deleteOp['deprecated'], true);
    });

    test('spec includes tags', () async {
      final response = await client.get('/openapi.json');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final tags = (body['tags'] as List).cast<Map<String, dynamic>>();

      expect(tags.any((t) => t['name'] == 'Users'), isTrue);
    });
  });
}
