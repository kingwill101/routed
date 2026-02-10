import 'dart:convert';

import 'package:routed/src/openapi/openapi_spec.dart';
import 'package:test/test.dart';

void main() {
  group('OpenApiSpec', () {
    test('minimal spec serializes correctly', () {
      final spec = OpenApiSpec(
        info: const OpenApiInfo(title: 'Test API', version: '1.0.0'),
      );
      final json = spec.toJson();

      expect(json['openapi'], '3.1.0');
      expect(json['info'], {'title': 'Test API', 'version': '1.0.0'});
      expect(json.containsKey('servers'), isFalse);
      expect(json.containsKey('paths'), isFalse);
      expect(json.containsKey('tags'), isFalse);
    });

    test('full spec serializes correctly', () {
      final spec = OpenApiSpec(
        info: const OpenApiInfo(
          title: 'My API',
          version: '2.0.0',
          description: 'A test API',
        ),
        servers: const [OpenApiServer(url: 'https://api.example.com')],
        paths: {
          '/users': OpenApiPathItem(
            get: const OpenApiOperation(
              summary: 'List users',
              operationId: 'listUsers',
              tags: ['users'],
              responses: {'200': OpenApiResponse(description: 'OK')},
            ),
          ),
        },
        tags: const [OpenApiTag(name: 'users', description: 'User ops')],
      );

      final json = spec.toJson();
      expect(json['openapi'], '3.1.0');
      expect((json['info'] as Map)['description'], 'A test API');
      expect(json['servers'], isA<List>());
      expect((json['servers'] as List).length, 1);
      expect(json['paths'], isA<Map>());
      expect((json['paths'] as Map).containsKey('/users'), isTrue);
      expect(json['tags'], isA<List>());
    });

    test('round-trip through JSON preserves data', () {
      final original = OpenApiSpec(
        info: const OpenApiInfo(
          title: 'Round Trip',
          version: '3.0.0',
          description: 'desc',
          termsOfService: 'https://example.com/tos',
          contact: {'name': 'Support', 'email': 'support@example.com'},
          license: {'name': 'MIT'},
        ),
        servers: const [
          OpenApiServer(url: 'https://api.example.com', description: 'Prod'),
          OpenApiServer(url: 'http://localhost:8080', description: 'Dev'),
        ],
        paths: {
          '/items': OpenApiPathItem(
            get: const OpenApiOperation(
              summary: 'Get items',
              description: 'Returns all items',
              operationId: 'getItems',
              tags: ['items'],
              parameters: [
                OpenApiParameter(
                  name: 'limit',
                  location: 'query',
                  required: false,
                  schema: {'type': 'integer', 'minimum': 1},
                ),
              ],
              responses: {
                '200': OpenApiResponse(
                  description: 'OK',
                  content: {
                    'application/json': OpenApiMediaType(
                      schema: {'type': 'array'},
                    ),
                  },
                ),
              },
            ),
            post: const OpenApiOperation(
              summary: 'Create item',
              operationId: 'createItem',
              tags: ['items'],
              requestBody: OpenApiRequestBody(
                description: 'Item data',
                required: true,
                content: {
                  'application/json': OpenApiMediaType(
                    schema: {
                      'type': 'object',
                      'properties': {
                        'name': {'type': 'string'},
                      },
                    },
                  ),
                },
              ),
              responses: {'201': OpenApiResponse(description: 'Created')},
              deprecated: true,
            ),
          ),
          '/items/{id}': OpenApiPathItem(
            delete: const OpenApiOperation(
              summary: 'Delete item',
              operationId: 'deleteItem',
              parameters: [
                OpenApiParameter(
                  name: 'id',
                  location: 'path',
                  required: true,
                  schema: {'type': 'string', 'format': 'uuid'},
                ),
              ],
              responses: {'204': OpenApiResponse(description: 'No Content')},
            ),
          ),
        },
        tags: const [OpenApiTag(name: 'items', description: 'Item management')],
      );

      final jsonStr = original.toJsonString();
      final decoded = jsonDecode(jsonStr) as Map<String, Object?>;
      final restored = OpenApiSpec.fromJson(decoded);
      final restoredJson = restored.toJson();
      final originalJson = original.toJson();

      // Compare JSON representations for equality.
      expect(jsonEncode(restoredJson), jsonEncode(originalJson));
    });

    test('toJsonString pretty formats correctly', () {
      final spec = OpenApiSpec(
        info: const OpenApiInfo(title: 'Test', version: '1.0.0'),
      );
      final pretty = spec.toJsonString(pretty: true);
      expect(pretty, contains('\n'));
      expect(pretty, contains('  '));

      final compact = spec.toJsonString();
      expect(compact, isNot(contains('\n')));
    });

    test('fromJson handles missing fields gracefully', () {
      final spec = OpenApiSpec.fromJson(<String, Object?>{});
      expect(spec.openapi, '3.1.0');
      expect(spec.info.title, 'Unknown');
      expect(spec.info.version, '0.0.0');
      expect(spec.servers, isEmpty);
      expect(spec.paths, isEmpty);
      expect(spec.tags, isEmpty);
    });
  });

  group('OpenApiInfo', () {
    test('serializes required fields only', () {
      const info = OpenApiInfo(title: 'API', version: '1.0.0');
      final json = info.toJson();
      expect(json, {'title': 'API', 'version': '1.0.0'});
      expect(json.containsKey('description'), isFalse);
    });

    test('serializes all fields', () {
      const info = OpenApiInfo(
        title: 'API',
        version: '1.0.0',
        description: 'desc',
        termsOfService: 'tos',
        contact: {'name': 'Admin'},
        license: {'name': 'MIT'},
      );
      final json = info.toJson();
      expect(json['description'], 'desc');
      expect(json['termsOfService'], 'tos');
      expect(json['contact'], {'name': 'Admin'});
      expect(json['license'], {'name': 'MIT'});
    });

    test('fromJson with missing fields', () {
      final info = OpenApiInfo.fromJson(<String, Object?>{});
      expect(info.title, 'Unknown');
      expect(info.version, '0.0.0');
      expect(info.description, isNull);
    });
  });

  group('OpenApiServer', () {
    test('serializes with url only', () {
      const server = OpenApiServer(url: 'https://api.example.com');
      expect(server.toJson(), {'url': 'https://api.example.com'});
    });

    test('serializes with description', () {
      const server = OpenApiServer(
        url: 'https://api.example.com',
        description: 'Production',
      );
      final json = server.toJson();
      expect(json['description'], 'Production');
    });

    test('round-trip', () {
      const original = OpenApiServer(
        url: 'http://localhost',
        description: 'Local',
      );
      final restored = OpenApiServer.fromJson(original.toJson());
      expect(restored.url, original.url);
      expect(restored.description, original.description);
    });
  });

  group('OpenApiTag', () {
    test('serializes with name only', () {
      const tag = OpenApiTag(name: 'users');
      expect(tag.toJson(), {'name': 'users'});
    });

    test('round-trip', () {
      const original = OpenApiTag(name: 'items', description: 'Item ops');
      final restored = OpenApiTag.fromJson(original.toJson());
      expect(restored.name, 'items');
      expect(restored.description, 'Item ops');
    });
  });

  group('OpenApiPathItem', () {
    test('empty path item serializes to empty map', () {
      const item = OpenApiPathItem();
      expect(item.toJson(), isEmpty);
    });

    test('operationFor returns correct operation', () {
      const op = OpenApiOperation(summary: 'test');
      final item = OpenApiPathItem(get: op);
      expect(item.operationFor('GET'), isNotNull);
      expect(item.operationFor('GET')!.summary, 'test');
      expect(item.operationFor('POST'), isNull);
      expect(item.operationFor('UNKNOWN'), isNull);
    });

    test('withOperation creates copy with new operation', () {
      const getOp = OpenApiOperation(summary: 'get');
      const postOp = OpenApiOperation(summary: 'post');

      final item = const OpenApiPathItem().withOperation('GET', getOp);
      expect(item.get?.summary, 'get');
      expect(item.post, isNull);

      final item2 = item.withOperation('POST', postOp);
      expect(item2.get?.summary, 'get');
      expect(item2.post?.summary, 'post');
    });

    test('all HTTP methods are preserved in withOperation', () {
      const op = OpenApiOperation(summary: 'x');
      var item = const OpenApiPathItem();
      for (final method in [
        'GET',
        'PUT',
        'POST',
        'DELETE',
        'OPTIONS',
        'HEAD',
        'PATCH',
      ]) {
        item = item.withOperation(method, op);
      }
      expect(item.get, isNotNull);
      expect(item.put, isNotNull);
      expect(item.post, isNotNull);
      expect(item.delete, isNotNull);
      expect(item.options, isNotNull);
      expect(item.head, isNotNull);
      expect(item.patch, isNotNull);
    });

    test('round-trip with multiple methods', () {
      final original = OpenApiPathItem(
        summary: 'User path',
        get: const OpenApiOperation(
          summary: 'List',
          operationId: 'list',
          responses: {'200': OpenApiResponse(description: 'OK')},
        ),
        post: const OpenApiOperation(summary: 'Create', operationId: 'create'),
        parameters: const [
          OpenApiParameter(name: 'x-trace', location: 'header'),
        ],
      );
      final restored = OpenApiPathItem.fromJson(original.toJson());
      expect(restored.summary, 'User path');
      expect(restored.get?.summary, 'List');
      expect(restored.post?.summary, 'Create');
      expect(restored.delete, isNull);
      expect(restored.parameters, hasLength(1));
    });
  });

  group('OpenApiOperation', () {
    test('minimal operation serializes to empty map', () {
      const op = OpenApiOperation();
      expect(op.toJson(), isEmpty);
    });

    test('deprecated only serialized when true', () {
      const opFalse = OpenApiOperation(deprecated: false);
      expect(opFalse.toJson().containsKey('deprecated'), isFalse);

      const opTrue = OpenApiOperation(deprecated: true);
      expect(opTrue.toJson()['deprecated'], isTrue);
    });

    test('full operation round-trip', () {
      const original = OpenApiOperation(
        summary: 'Create user',
        description: 'Creates a new user account',
        operationId: 'createUser',
        tags: ['users', 'admin'],
        parameters: [
          OpenApiParameter(
            name: 'x-api-key',
            location: 'header',
            required: true,
            schema: {'type': 'string'},
          ),
        ],
        requestBody: OpenApiRequestBody(
          description: 'User data',
          required: true,
          content: {
            'application/json': OpenApiMediaType(
              schema: {'type': 'object'},
              example: {'name': 'Alice'},
            ),
          },
        ),
        responses: {
          '201': OpenApiResponse(description: 'Created'),
          '400': OpenApiResponse(description: 'Bad Request'),
        },
        deprecated: true,
      );

      final json = original.toJson();
      final restored = OpenApiOperation.fromJson(json);
      expect(restored.summary, 'Create user');
      expect(restored.description, 'Creates a new user account');
      expect(restored.operationId, 'createUser');
      expect(restored.tags, ['users', 'admin']);
      expect(restored.parameters, hasLength(1));
      expect(restored.parameters[0].name, 'x-api-key');
      expect(restored.requestBody, isNotNull);
      expect(restored.requestBody!.required, isTrue);
      expect(restored.responses, hasLength(2));
      expect(restored.deprecated, isTrue);
    });
  });

  group('OpenApiParameter', () {
    test('path parameter is always required', () {
      const param = OpenApiParameter(name: 'id', location: 'path');
      expect(param.isRequired, isTrue);
      final json = param.toJson();
      expect(json['required'], isTrue);
      expect(json['in'], 'path');
    });

    test('query parameter defaults to not required', () {
      const param = OpenApiParameter(name: 'q', location: 'query');
      expect(param.isRequired, isFalse);
    });

    test('explicit required overrides default', () {
      const param = OpenApiParameter(
        name: 'q',
        location: 'query',
        required: true,
      );
      expect(param.isRequired, isTrue);
    });

    test('empty description is not serialized', () {
      const param = OpenApiParameter(
        name: 'id',
        location: 'path',
        description: '',
      );
      final json = param.toJson();
      expect(json.containsKey('description'), isFalse);
    });

    test('round-trip with all fields', () {
      const original = OpenApiParameter(
        name: 'limit',
        location: 'query',
        description: 'Max items',
        required: false,
        schema: {'type': 'integer', 'minimum': 1, 'maximum': 100},
        example: 25,
      );
      final restored = OpenApiParameter.fromJson(original.toJson());
      expect(restored.name, 'limit');
      expect(restored.location, 'query');
      expect(restored.description, 'Max items');
      expect(restored.required, isFalse);
      expect(restored.schema?['type'], 'integer');
      expect(restored.example, 25);
    });

    test('fromJson handles missing fields', () {
      final param = OpenApiParameter.fromJson(<String, Object?>{});
      expect(param.name, '');
      expect(param.location, 'query');
    });
  });

  group('OpenApiRequestBody', () {
    test('minimal request body', () {
      const body = OpenApiRequestBody();
      final json = body.toJson();
      expect(json.containsKey('required'), isFalse);
      expect(json.containsKey('content'), isFalse);
    });

    test('required body serializes required field', () {
      const body = OpenApiRequestBody(required: true);
      expect(body.toJson()['required'], isTrue);
    });

    test('round-trip', () {
      const original = OpenApiRequestBody(
        description: 'Payload',
        required: true,
        content: {
          'application/json': OpenApiMediaType(
            schema: {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          ),
          'application/xml': OpenApiMediaType(schema: {'type': 'string'}),
        },
      );
      final restored = OpenApiRequestBody.fromJson(original.toJson());
      expect(restored.description, 'Payload');
      expect(restored.required, isTrue);
      expect(restored.content, hasLength(2));
      expect(restored.content.containsKey('application/json'), isTrue);
    });
  });

  group('OpenApiMediaType', () {
    test('empty media type', () {
      const mt = OpenApiMediaType();
      expect(mt.toJson(), isEmpty);
    });

    test('with schema and example', () {
      const mt = OpenApiMediaType(schema: {'type': 'string'}, example: 'hello');
      final json = mt.toJson();
      expect(json['schema'], {'type': 'string'});
      expect(json['example'], 'hello');
    });
  });

  group('OpenApiResponse', () {
    test('description-only response', () {
      const resp = OpenApiResponse(description: 'OK');
      final json = resp.toJson();
      expect(json, {'description': 'OK'});
    });

    test('round-trip with content and headers', () {
      const original = OpenApiResponse(
        description: 'Success',
        content: {
          'application/json': OpenApiMediaType(schema: {'type': 'object'}),
        },
        headers: {
          'X-Rate-Limit': {
            'schema': {'type': 'integer'},
          },
        },
      );
      final restored = OpenApiResponse.fromJson(original.toJson());
      expect(restored.description, 'Success');
      expect(restored.content, hasLength(1));
      expect(restored.headers, isNotNull);
      expect(restored.headers!.containsKey('X-Rate-Limit'), isTrue);
    });

    test('fromJson with missing description defaults to empty string', () {
      final resp = OpenApiResponse.fromJson(<String, Object?>{});
      expect(resp.description, '');
    });
  });
}
