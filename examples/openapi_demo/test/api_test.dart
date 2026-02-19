import 'dart:convert';
import 'dart:io';

import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

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
      expect(paths, contains('/api/v1/catalog/v2/health'));
      expect(paths, contains('/api/v1/catalog/v2/products'));
      expect(paths, contains('/api/v1/catalog/v2/products/{sku}'));
      expect(paths, contains('/api/v1/catalog/v2/raw'));
      expect(paths, contains('/api/v1/catalog/v2/inline'));
      expect(paths, contains('/api/v1/admin/v2/inline'));
    });

    test('spec merges metadata from annotations and dartdoc', () async {
      final response = await client.get('/openapi.json');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = body['paths'] as Map<String, dynamic>;

      final health = paths['/api/v1/catalog/v2/health'] as Map<String, dynamic>;
      final healthGet = health['get'] as Map<String, dynamic>;
      expect(healthGet['summary'], 'Catalog health check.');
      expect(
        healthGet['description'],
        'Demonstrates Dartdoc extraction from an inline closure route.',
      );

      final products =
          paths['/api/v1/catalog/v2/products'] as Map<String, dynamic>;
      final productsGet = products['get'] as Map<String, dynamic>;
      expect(productsGet['summary'], 'List catalog products');
      // schema operationId should win over @OperationId annotation
      expect(productsGet['operationId'], 'catalogProducts');
      expect(productsGet['tags'], contains('Catalog'));

      final productBySku =
          paths['/api/v1/catalog/v2/products/{sku}'] as Map<String, dynamic>;
      final bySkuGet = productBySku['get'] as Map<String, dynamic>;
      expect(bySkuGet['summary'], 'Get catalog product by sku');
      final responses = bySkuGet['responses'] as Map<String, dynamic>;
      expect(responses, contains('404'));

      final catalogInline =
          paths['/api/v1/catalog/v2/inline'] as Map<String, dynamic>;
      final adminInline =
          paths['/api/v1/admin/v2/inline'] as Map<String, dynamic>;
      expect(
        (catalogInline['get'] as Map<String, dynamic>)['summary'],
        'Catalog inline docs route.',
      );
      expect(
        (adminInline['get'] as Map<String, dynamic>)['summary'],
        'Admin inline docs route.',
      );
    });

    test('route without schema or docs falls back to defaults', () async {
      final response = await client.get('/openapi.json');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = body['paths'] as Map<String, dynamic>;

      final raw = paths['/api/v1/catalog/v2/raw'] as Map<String, dynamic>;
      final rawGet = raw['get'] as Map<String, dynamic>;
      expect(rawGet.containsKey('summary'), isFalse);
      expect(rawGet['operationId'], 'getApiV1CatalogV2Raw');
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

    test('runtime and generated specs match for stress routes', () async {
      final runtimeResponse = await client.get('/openapi.json');
      runtimeResponse.assertStatus(200);
      final runtimeSpec =
          jsonDecode(runtimeResponse.body) as Map<String, dynamic>;

      final generatedSpec = _readGeneratedSpec();

      expect(runtimeSpec['openapi'], equals(generatedSpec['openapi']));
      final runtimeInfo = runtimeSpec['info'] as Map<String, dynamic>;
      final generatedInfo = generatedSpec['info'] as Map<String, dynamic>;
      expect(runtimeInfo['title'], equals(generatedInfo['title']));
      expect(runtimeInfo['version'], equals(generatedInfo['version']));

      final runtimePaths = runtimeSpec['paths'] as Map<String, dynamic>;
      final generatedPaths = generatedSpec['paths'] as Map<String, dynamic>;

      const stressPaths = [
        '/api/v1/catalog/v2/health',
        '/api/v1/catalog/v2/inline',
        '/api/v1/admin/v2/inline',
        '/api/v1/catalog/v2/products',
        '/api/v1/catalog/v2/products/{sku}',
        '/api/v1/catalog/v2/raw',
      ];

      for (final path in stressPaths) {
        expect(runtimePaths, contains(path));
        expect(generatedPaths, contains(path));
        expect(runtimePaths[path], equals(generatedPaths[path]));
      }
    });
  });
}

Map<String, dynamic> _readGeneratedSpec() {
  final candidates = <String>[
    'examples/openapi_demo/lib/generated/openapi.json',
    'lib/generated/openapi.json',
  ];

  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync());
      return json as Map<String, dynamic>;
    }
  }

  fail(
    'Generated OpenAPI spec not found. Run `dart run routed spec` and '
    '`dart run build_runner build --delete-conflicting-outputs` in '
    '`examples/openapi_demo` before running this test.',
  );
}
