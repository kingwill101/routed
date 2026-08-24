import 'package:routed_openapi/routed_openapi.dart';
import 'package:test/test.dart';

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
        body: BodySchema(
          description: 'User payload',
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
      expect((json['params']! as List<Object?>).length, 1);
      expect(json['responses'], isA<List<Object?>>());
      expect((json['responses']! as List<Object?>).length, 2);
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
}
