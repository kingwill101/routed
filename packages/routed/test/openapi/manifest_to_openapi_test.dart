import 'package:routed/src/engine/route_manifest.dart';
import 'package:routed/src/openapi/manifest_to_openapi.dart';
import 'package:routed/src/openapi/openapi_spec.dart';
import 'package:routed/src/openapi/schema.dart';
import 'package:routed/src/openapi/annotations.dart';
import 'package:test/test.dart';

void main() {
  group('manifestToOpenApi', () {
    test('empty manifest produces minimal spec', () {
      final manifest = RouteManifest(routes: []);
      final spec = manifestToOpenApi(manifest);

      expect(spec.openapi, '3.1.0');
      expect(spec.info.title, 'API');
      expect(spec.info.version, '1.0.0');
      expect(spec.paths, isEmpty);
      expect(spec.tags, isEmpty);
    });

    test('config overrides title, version, and description', () {
      final manifest = RouteManifest(routes: []);
      final spec = manifestToOpenApi(
        manifest,
        config: const OpenApiConfig(
          title: 'My Service',
          version: '2.5.0',
          description: 'A cool API',
        ),
      );

      expect(spec.info.title, 'My Service');
      expect(spec.info.version, '2.5.0');
      expect(spec.info.description, 'A cool API');
    });

    test('config servers are passed through', () {
      final manifest = RouteManifest(routes: []);
      final spec = manifestToOpenApi(
        manifest,
        config: const OpenApiConfig(
          servers: [
            OpenApiServer(url: 'https://api.example.com', description: 'Prod'),
          ],
        ),
      );

      expect(spec.servers, hasLength(1));
      expect(spec.servers[0].url, 'https://api.example.com');
    });

    test('simple GET route without schema', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'GET', path: '/users')],
      );
      final spec = manifestToOpenApi(manifest);

      expect(spec.paths, hasLength(1));
      expect(spec.paths.containsKey('/users'), isTrue);

      final pathItem = spec.paths['/users']!;
      expect(pathItem.get, isNotNull);
      expect(pathItem.post, isNull);

      // Default 200 response should be generated.
      expect(pathItem.get!.responses, hasLength(1));
      expect(pathItem.get!.responses.containsKey('200'), isTrue);
    });

    test('path params are converted from :id to {id}', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(method: 'GET', path: '/users/:id/posts/:postId'),
        ],
      );
      final spec = manifestToOpenApi(manifest);

      expect(spec.paths.containsKey('/users/{id}/posts/{postId}'), isTrue);

      final op = spec.paths['/users/{id}/posts/{postId}']!.get!;
      final paramNames = op.parameters.map((p) => p.name).toList();
      expect(paramNames, contains('id'));
      expect(paramNames, contains('postId'));

      // Path params should always be required.
      for (final p in op.parameters) {
        expect(p.isRequired, isTrue);
        expect(p.location, 'path');
      }
    });

    test('multiple methods on same path merge into one path item', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(method: 'GET', path: '/items'),
          RouteManifestEntry(method: 'POST', path: '/items'),
          RouteManifestEntry(method: 'DELETE', path: '/items/:id'),
        ],
      );
      final spec = manifestToOpenApi(manifest);

      expect(spec.paths, hasLength(2));

      final itemsPath = spec.paths['/items']!;
      expect(itemsPath.get, isNotNull);
      expect(itemsPath.post, isNotNull);
      expect(itemsPath.delete, isNull);

      final itemIdPath = spec.paths['/items/{id}']!;
      expect(itemIdPath.delete, isNotNull);
      expect(itemIdPath.get, isNull);
    });

    test('operationId generated from route name', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            name: 'users.index',
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.get!;
      expect(op.operationId, 'usersIndex');
    });

    test('operationId generated from method+path when no name', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'POST', path: '/users')],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.post!;
      expect(op.operationId, 'postUsers');
    });

    test('operationId for root path', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'GET', path: '/')],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/']!.get!;
      expect(op.operationId, 'getRoot');
    });

    test('schema summary and description are passed through', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            schema: const RouteSchema(
              summary: 'List users',
              description: 'Returns all users with pagination',
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.get!;
      expect(op.summary, 'List users');
      expect(op.description, 'Returns all users with pagination');
    });

    test('schema tags are collected and sorted', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            schema: const RouteSchema(tags: ['users', 'admin']),
          ),
          RouteManifestEntry(
            method: 'GET',
            path: '/items',
            schema: const RouteSchema(tags: ['items']),
          ),
          RouteManifestEntry(
            method: 'POST',
            path: '/users',
            schema: const RouteSchema(tags: ['users']),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);

      final tagNames = spec.tags.map((t) => t.name).toList();
      expect(tagNames, ['admin', 'items', 'users']);
    });

    test('deprecated flag is passed through', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/old',
            schema: const RouteSchema(deprecated: true),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      expect(spec.paths['/old']!.get!.deprecated, isTrue);
    });

    test('hidden routes are excluded by default', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/health',
            schema: const RouteSchema(hidden: true),
          ),
          RouteManifestEntry(method: 'GET', path: '/users'),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      expect(spec.paths.containsKey('/health'), isFalse);
      expect(spec.paths.containsKey('/users'), isTrue);
    });

    test('hidden routes are included when includeHidden is true', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/health',
            schema: const RouteSchema(hidden: true),
          ),
        ],
      );
      final spec = manifestToOpenApi(
        manifest,
        config: const OpenApiConfig(includeHidden: true),
      );
      expect(spec.paths.containsKey('/health'), isTrue);
    });

    test('fallback routes are skipped', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(method: 'GET', path: '/*', isFallback: true),
          RouteManifestEntry(method: 'GET', path: '/users'),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      expect(spec.paths, hasLength(1));
      expect(spec.paths.containsKey('/users'), isTrue);
    });

    test('explicit operationId from schema is used', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            schema: const RouteSchema(operationId: 'fetchAllUsers'),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      expect(spec.paths['/users']!.get!.operationId, 'fetchAllUsers');
    });
  });

  group('request body generation', () {
    test('body schema produces request body', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'POST',
            path: '/users',
            schema: const RouteSchema(
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
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.post!;

      expect(op.requestBody, isNotNull);
      expect(op.requestBody!.description, 'User payload');
      expect(op.requestBody!.required, isTrue);
      expect(op.requestBody!.content.containsKey('application/json'), isTrue);
      expect(
        op.requestBody!.content['application/json']!.schema?['type'],
        'object',
      );
    });

    test('validation rules auto-generate request body', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'POST',
            path: '/users',
            schema: RouteSchema.fromRules({
              'name': 'required|string|min:2|max:100',
              'email': 'required|email',
            }),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.post!;

      expect(op.requestBody, isNotNull);
      expect(op.requestBody!.required, isTrue);

      final schema = op.requestBody!.content['application/json']!.schema!;
      expect(schema['type'], 'object');
      expect(schema['required'], containsAll(['name', 'email']));

      final props = schema['properties'] as Map<String, Object?>;
      expect(props.containsKey('name'), isTrue);
      expect(props.containsKey('email'), isTrue);
    });

    test('body schema takes precedence over validation rules', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'POST',
            path: '/users',
            schema: const RouteSchema(
              body: BodySchema(
                description: 'Explicit body',
                required: true,
                jsonSchema: {'type': 'object'},
              ),
              validationRules: {'name': 'required|string'},
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.post!;

      expect(op.requestBody!.description, 'Explicit body');
      // The explicit body schema should be used, not the validation rules.
      expect(op.requestBody!.content['application/json']!.schema, {
        'type': 'object',
      });
    });
  });

  group('parameter generation', () {
    test('path params extracted and merged with schema params', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users/:id',
            schema: RouteSchema(
              params: [
                const ParamSchema(
                  'id',
                  location: ParamLocation.path,
                  description: 'User ID',
                  jsonSchema: {'type': 'string', 'format': 'uuid'},
                  example: '550e8400-e29b-41d4-a716-446655440000',
                ),
              ],
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users/{id}']!.get!;

      expect(op.parameters, hasLength(1));
      final param = op.parameters[0];
      expect(param.name, 'id');
      expect(param.location, 'path');
      expect(param.isRequired, isTrue);
      expect(param.description, 'User ID');
      expect(param.schema?['format'], 'uuid');
      expect(param.example, '550e8400-e29b-41d4-a716-446655440000');
    });

    test('query params from schema are added', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users',
            schema: RouteSchema(
              params: [
                const ParamSchema(
                  'page',
                  location: ParamLocation.query,
                  description: 'Page number',
                  required: false,
                  jsonSchema: {'type': 'integer', 'minimum': 1},
                ),
                const ParamSchema(
                  'limit',
                  location: ParamLocation.query,
                  description: 'Items per page',
                  required: false,
                  jsonSchema: {'type': 'integer', 'minimum': 1, 'maximum': 100},
                ),
              ],
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.get!;

      expect(op.parameters, hasLength(2));
      expect(op.parameters[0].name, 'page');
      expect(op.parameters[0].location, 'query');
      expect(op.parameters[0].isRequired, isFalse);
      expect(op.parameters[1].name, 'limit');
    });

    test('header params from schema are added', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/data',
            schema: RouteSchema(
              params: [
                const ParamSchema(
                  'X-Api-Key',
                  location: ParamLocation.header,
                  description: 'API key',
                  required: true,
                ),
              ],
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/data']!.get!;

      expect(op.parameters, hasLength(1));
      expect(op.parameters[0].name, 'X-Api-Key');
      expect(op.parameters[0].location, 'header');
      expect(op.parameters[0].isRequired, isTrue);
    });

    test('path params get default string schema when not in schema', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'GET', path: '/users/:id')],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users/{id}']!.get!;

      expect(op.parameters, hasLength(1));
      expect(op.parameters[0].schema, {'type': 'string'});
    });
  });

  group('response generation', () {
    test('explicit responses from schema', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'POST',
            path: '/users',
            schema: const RouteSchema(
              responses: [
                ResponseSchema(
                  201,
                  description: 'User created',
                  contentType: 'application/json',
                  jsonSchema: {
                    'type': 'object',
                    'properties': {
                      'id': {'type': 'string'},
                    },
                  },
                ),
                ResponseSchema(422, description: 'Validation failed'),
              ],
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/users']!.post!;

      expect(op.responses, hasLength(2));
      expect(op.responses.containsKey('201'), isTrue);
      expect(op.responses.containsKey('422'), isTrue);
      expect(op.responses['201']!.description, 'User created');
      expect(
        op.responses['201']!.content?['application/json']?.schema?['type'],
        'object',
      );
      expect(op.responses['422']!.description, 'Validation failed');
    });

    test('default 200 response when none specified', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'GET', path: '/ping')],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/ping']!.get!;

      expect(op.responses, hasLength(1));
      expect(op.responses['200']!.description, 'Successful response');
    });

    test('response with empty description gets default status description', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'DELETE',
            path: '/items/:id',
            schema: const RouteSchema(responses: [ResponseSchema(204)]),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/items/{id}']!.delete!;
      expect(op.responses['204']!.description, 'No Content');
    });

    test('response with headers', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/limited',
            schema: const RouteSchema(
              responses: [
                ResponseSchema(
                  200,
                  description: 'OK',
                  headers: {
                    'X-Rate-Limit': {
                      'schema': {'type': 'integer'},
                    },
                  },
                ),
              ],
            ),
          ),
        ],
      );
      final spec = manifestToOpenApi(manifest);
      final op = spec.paths['/limited']!.get!;
      expect(op.responses['200']!.headers, isNotNull);
      expect(op.responses['200']!.headers!.containsKey('X-Rate-Limit'), isTrue);
    });
  });

  group('OpenApiConfig', () {
    test('defaults are sensible', () {
      const config = OpenApiConfig();
      expect(config.title, 'API');
      expect(config.version, '1.0.0');
      expect(config.description, isNull);
      expect(config.servers, isEmpty);
      expect(config.includeHidden, isFalse);
    });
  });

  group('complex scenarios', () {
    test('full API with multiple routes and schemas', () {
      final manifest = RouteManifest(
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
            schema: RouteSchema(
              summary: 'Create user',
              tags: const ['users'],
              body: const BodySchema(
                required: true,
                jsonSchema: {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'email': {'type': 'string', 'format': 'email'},
                  },
                  'required': ['name', 'email'],
                },
              ),
              responses: const [
                ResponseSchema(201, description: 'Created'),
                ResponseSchema(422, description: 'Validation error'),
              ],
            ),
          ),
          RouteManifestEntry(
            method: 'GET',
            path: '/users/:id',
            name: 'users.show',
            schema: RouteSchema(
              summary: 'Get user by ID',
              tags: const ['users'],
              params: [
                const ParamSchema(
                  'id',
                  location: ParamLocation.path,
                  description: 'User ID',
                  jsonSchema: {'type': 'integer'},
                ),
              ],
              responses: const [
                ResponseSchema(200, description: 'User found'),
                ResponseSchema(404, description: 'User not found'),
              ],
            ),
          ),
          // Fallback — should be skipped.
          RouteManifestEntry(method: 'GET', path: '/*', isFallback: true),
          // Hidden — should be skipped.
          RouteManifestEntry(
            method: 'GET',
            path: '/metrics',
            schema: const RouteSchema(hidden: true),
          ),
        ],
      );

      final spec = manifestToOpenApi(
        manifest,
        config: const OpenApiConfig(
          title: 'User Service',
          version: '1.2.0',
          description: 'User management API',
          servers: [OpenApiServer(url: 'https://api.users.dev')],
        ),
      );

      // Verify info.
      expect(spec.info.title, 'User Service');
      expect(spec.info.version, '1.2.0');

      // 3 routes visible (fallback + hidden excluded).
      expect(spec.paths, hasLength(2)); // /users and /users/{id}

      // /users should have GET and POST.
      final usersPath = spec.paths['/users']!;
      expect(usersPath.get, isNotNull);
      expect(usersPath.post, isNotNull);
      expect(usersPath.get!.operationId, 'usersIndex');
      expect(usersPath.post!.operationId, 'usersStore');
      expect(usersPath.post!.requestBody, isNotNull);
      expect(usersPath.post!.responses, hasLength(2));

      // /users/{id} should have GET.
      final userIdPath = spec.paths['/users/{id}']!;
      expect(userIdPath.get, isNotNull);
      expect(userIdPath.get!.operationId, 'usersShow');
      expect(userIdPath.get!.parameters, hasLength(1));
      expect(userIdPath.get!.parameters[0].name, 'id');
      expect(userIdPath.get!.responses, hasLength(2));

      // Tags should be collected and sorted.
      expect(spec.tags.map((t) => t.name), ['users']);

      // Server should be there.
      expect(spec.servers, hasLength(1));

      // Should produce valid JSON.
      final jsonStr = spec.toJsonString(pretty: true);
      expect(jsonStr, contains('"openapi": "3.1.0"'));
      expect(jsonStr, contains('"User Service"'));
    });
  });
}
