import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

import '../test_engine.dart';

void main() {
  group('RouteSchema serialization', () {
    test('toJson omits null/empty fields', () {
      const schema = RouteSchema(summary: 'Get users');
      final json = schema.toJson();

      expect(json['summary'], 'Get users');
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('tags'), isFalse);
      expect(json.containsKey('body'), isFalse);
      expect(json.containsKey('params'), isFalse);
      expect(json.containsKey('responses'), isFalse);
      expect(json.containsKey('validationRules'), isFalse);
    });

    test('toJson includes all populated fields', () {
      const schema = RouteSchema(
        summary: 'Create user',
        description: 'Creates a new user account',
        tags: ['users', 'admin'],
        operationId: 'createUser',
        deprecated: true,
        hidden: false,
        body: BodySchema(
          description: 'User payload',
          contentType: 'application/json',
          required: true,
          jsonSchema: {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
          },
        ),
        params: [
          ParamSchema(
            'id',
            location: ParamLocation.path,
            description: 'User ID',
            required: true,
            jsonSchema: {'type': 'integer'},
            example: 42,
          ),
        ],
        responses: [
          ResponseSchema(201, description: 'Created'),
          ResponseSchema(422, description: 'Validation failed'),
        ],
        validationRules: {'name': 'required|string', 'email': 'required|email'},
      );

      final json = schema.toJson();

      expect(json['summary'], 'Create user');
      expect(json['description'], 'Creates a new user account');
      expect(json['tags'], ['users', 'admin']);
      expect(json['operationId'], 'createUser');
      expect(json['deprecated'], true);
      expect(json.containsKey('hidden'), isFalse); // false is omitted
      expect(json['body'], isA<Map<String, Object?>>());
      expect(json['params'], isA<List<Object?>>());
      expect((json['params'] as List<Object?>).length, 1);
      expect(json['responses'], isA<List<Object?>>());
      expect((json['responses'] as List<Object?>).length, 2);
      expect(json['validationRules'], {
        'name': 'required|string',
        'email': 'required|email',
      });
    });

    test('roundtrips through toJson/fromJson', () {
      const original = RouteSchema(
        summary: 'Update user',
        description: 'Updates an existing user',
        tags: ['users'],
        operationId: 'updateUser',
        deprecated: true,
        body: BodySchema(
          description: 'Update payload',
          contentType: 'application/json',
          required: true,
          jsonSchema: {'type': 'object'},
        ),
        params: [
          ParamSchema(
            'id',
            location: ParamLocation.path,
            description: 'User ID',
            required: true,
            jsonSchema: {'type': 'integer'},
            example: 7,
          ),
          ParamSchema(
            'fields',
            location: ParamLocation.query,
            description: 'Fields to return',
          ),
        ],
        responses: [
          ResponseSchema(200, description: 'Updated'),
          ResponseSchema(404, description: 'Not found'),
        ],
        validationRules: {'name': 'string|min:1'},
      );

      final json = original.toJson();
      final restored = RouteSchema.fromJson(json);

      expect(restored.summary, original.summary);
      expect(restored.description, original.description);
      expect(restored.tags, original.tags);
      expect(restored.operationId, original.operationId);
      expect(restored.deprecated, original.deprecated);
      expect(restored.hidden, original.hidden);
      expect(restored.body!.description, original.body!.description);
      expect(restored.body!.contentType, original.body!.contentType);
      expect(restored.body!.required, original.body!.required);
      expect(restored.body!.jsonSchema, original.body!.jsonSchema);
      expect(restored.params!.length, original.params!.length);
      expect(restored.params![0].name, 'id');
      expect(restored.params![0].location, ParamLocation.path);
      expect(restored.params![0].isRequired, isTrue);
      expect(restored.params![0].example, 7);
      expect(restored.params![1].name, 'fields');
      expect(restored.params![1].location, ParamLocation.query);
      expect(restored.responses!.length, 2);
      expect(restored.responses![0].statusCode, 200);
      expect(restored.responses![1].statusCode, 404);
      expect(restored.validationRules, {'name': 'string|min:1'});
    });

    test('fromJson handles minimal input', () {
      final schema = RouteSchema.fromJson(<String, Object?>{});
      expect(schema.summary, isNull);
      expect(schema.description, isNull);
      expect(schema.tags, isNull);
      expect(schema.deprecated, isFalse);
      expect(schema.hidden, isFalse);
      expect(schema.body, isNull);
      expect(schema.params, isNull);
      expect(schema.responses, isNull);
      expect(schema.validationRules, isNull);
    });
  });

  group('RouteManifestEntry with schema', () {
    test('toJson includes schema when present', () {
      final entry = RouteManifestEntry(
        method: 'POST',
        path: '/users',
        name: 'users.store',
        handlerIdentity: const HandlerIdentity(
          functionRef: 'createUser',
          sourceFile: 'lib/app.dart',
          sourceLine: 88,
          sourceColumn: 9,
        ),
        schema: const RouteSchema(
          summary: 'Create user',
          validationRules: {'name': 'required'},
        ),
      );

      final json = entry.toJson();
      expect(json['schema'], isA<Map<String, Object?>>());
      expect(
        (json['schema'] as Map<String, Object?>)['summary'],
        'Create user',
      );
      expect((json['schema'] as Map<String, Object?>)['validationRules'], {
        'name': 'required',
      });
      expect(json['handlerIdentity'], isA<Map<String, Object?>>());
      final identity = json['handlerIdentity'] as Map<String, Object?>;
      expect(identity['sourceFile'], 'lib/app.dart');
      expect(identity['sourceLine'], 88);
      expect(identity['sourceColumn'], 9);
    });

    test('toJson omits schema when null', () {
      final entry = RouteManifestEntry(method: 'GET', path: '/health');

      final json = entry.toJson();
      expect(json.containsKey('schema'), isFalse);
    });

    test('fromJson deserializes schema', () {
      final json = <String, Object?>{
        'method': 'PUT',
        'path': '/users/:id',
        'name': 'users.update',
        'handlerIdentity': {
          'functionRef': 'updateUser',
          'sourceFile': 'package:demo/routes.dart',
          'sourceLine': 21,
          'sourceColumn': 5,
        },
        'schema': {
          'summary': 'Update user',
          'tags': ['users'],
          'validationRules': {'name': 'string|min:1'},
        },
      };

      final entry = RouteManifestEntry.fromJson(json);
      expect(entry.schema, isNotNull);
      expect(entry.schema!.summary, 'Update user');
      expect(entry.schema!.tags, ['users']);
      expect(entry.schema!.validationRules, {'name': 'string|min:1'});
      expect(entry.handlerIdentity, isNotNull);
      expect(entry.handlerIdentity!.functionRef, 'updateUser');
      expect(entry.handlerIdentity!.sourceFile, 'package:demo/routes.dart');
      expect(entry.handlerIdentity!.sourceLine, 21);
      expect(entry.handlerIdentity!.sourceColumn, 5);
    });

    test('fromJson handles missing schema', () {
      final json = <String, Object?>{'method': 'GET', 'path': '/health'};

      final entry = RouteManifestEntry.fromJson(json);
      expect(entry.schema, isNull);
    });

    test('manifest entry roundtrips through JSON', () {
      final original = RouteManifestEntry(
        method: 'DELETE',
        path: '/users/:id',
        name: 'users.destroy',
        schema: const RouteSchema(
          summary: 'Delete user',
          deprecated: true,
          responses: [
            ResponseSchema(204, description: 'No content'),
            ResponseSchema(404, description: 'Not found'),
          ],
        ),
      );

      final json = original.toJson();
      final restored = RouteManifestEntry.fromJson(json);

      expect(restored.method, 'DELETE');
      expect(restored.path, '/users/:id');
      expect(restored.name, 'users.destroy');
      expect(restored.schema, isNotNull);
      expect(restored.schema!.summary, 'Delete user');
      expect(restored.schema!.deprecated, isTrue);
      expect(restored.schema!.responses!.length, 2);
      expect(restored.schema!.responses![0].statusCode, 204);
    });
  });

  group('RouteManifest with schema', () {
    test('full manifest roundtrips through JSON string', () {
      final manifest = RouteManifest(
        generatedAt: DateTime.utc(2025, 1, 1),
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            name: 'users.index',
            schema: const RouteSchema(summary: 'List users', tags: ['users']),
          ),
          RouteManifestEntry(
            method: 'POST',
            path: '/users',
            name: 'users.store',
            schema: const RouteSchema(
              summary: 'Create user',
              body: BodySchema(description: 'User payload', required: true),
              validationRules: {
                'name': 'required|string',
                'email': 'required|email',
              },
            ),
          ),
          RouteManifestEntry(
            method: 'GET',
            path: '/health',
            // No schema
          ),
        ],
      );

      final jsonString = manifest.toJsonString(pretty: true);
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = RouteManifest.fromJson(decoded);

      expect(restored.routes.length, 3);

      // First route has schema
      expect(restored.routes[0].schema, isNotNull);
      expect(restored.routes[0].schema!.summary, 'List users');
      expect(restored.routes[0].schema!.tags, ['users']);

      // Second route has schema with body and validation rules
      expect(restored.routes[1].schema, isNotNull);
      expect(restored.routes[1].schema!.summary, 'Create user');
      expect(restored.routes[1].schema!.body, isNotNull);
      expect(restored.routes[1].schema!.body!.required, isTrue);
      expect(restored.routes[1].schema!.validationRules, isNotNull);
      expect(
        restored.routes[1].schema!.validationRules!['email'],
        'required|email',
      );

      // Third route has no schema
      expect(restored.routes[2].schema, isNull);
    });
  });

  group('Engine manifest integration', () {
    test('buildRouteManifest includes schema from registered routes', () async {
      final engine = testEngine();
      engine.get(
        '/users',
        (ctx) => ctx.json({'users': <String>[]}),
        schema: const RouteSchema(summary: 'List users', tags: ['users']),
      );
      engine.post(
        '/users',
        (ctx) => ctx.json({'created': true}),
        schema: RouteSchema.fromRules({
          'name': 'required|string',
          'email': 'required|email',
        }),
      );
      engine.get('/health', (ctx) => ctx.json({'ok': true}));

      // Must initialize before building manifest
      await engine.initialize();

      final manifest = engine.buildRouteManifest();

      // Find routes by path+method
      final getUsers = manifest.routes.firstWhere(
        (r) => r.method == 'GET' && r.path == '/users',
      );
      final postUsers = manifest.routes.firstWhere(
        (r) => r.method == 'POST' && r.path == '/users',
      );
      final health = manifest.routes.firstWhere((r) => r.path == '/health');

      expect(getUsers.schema, isNotNull);
      expect(getUsers.schema!.summary, 'List users');
      expect(getUsers.schema!.tags, ['users']);
      expect(getUsers.handlerIdentity, isNotNull);
      expect(getUsers.handlerIdentity!.method, 'GET');
      expect(getUsers.handlerIdentity!.path, '/users');

      expect(postUsers.schema, isNotNull);
      expect(postUsers.schema!.validationRules, isNotNull);
      expect(postUsers.schema!.validationRules!['name'], 'required|string');
      expect(postUsers.handlerIdentity, isNotNull);

      expect(health.schema, isNull);

      // Verify it survives JSON roundtrip
      final jsonString = manifest.toJsonString();
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = RouteManifest.fromJson(decoded);

      final restoredGetUsers = restored.routes.firstWhere(
        (r) => r.method == 'GET' && r.path == '/users',
      );
      expect(restoredGetUsers.schema!.summary, 'List users');
    });
  });
}
