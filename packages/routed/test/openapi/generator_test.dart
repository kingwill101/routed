import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('generateOpenApiDocument', () {
    test('respects route metadata and adds derived details', () {
      final manifest = RouteManifest(
        routes: [
          RouteManifestEntry(
            method: 'GET',
            path: '/users/{id:int}',
            name: 'users.show',
            constraints: {
              'openapi': {
                'summary': 'Fetch a user',
                'responses': {
                  '200': {
                    'description': 'User found',
                    'content': {
                      'application/json': {
                        'schema': {
                          'type': 'object',
                          'properties': {
                            'id': {'type': 'integer'},
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          ),
        ],
      );

      final document = generateOpenApiDocument(
        manifest,
        info: const OpenApiDocumentInfo(title: 'Demo', version: '1.0.0'),
      );

      expect(document['openapi'], equals('3.1.0'));
      final paths = document['paths'] as Map<String, Object?>;
      expect(paths, contains('/users/{id:int}'));
      final operations = paths['/users/{id:int}'] as Map<String, Object?>;
      final getOperation = operations['get'] as Map<String, Object?>;
      expect(getOperation['summary'], equals('Fetch a user'));
      expect(getOperation['tags'], equals(['users']));
      expect(getOperation['operationId'], equals('get_users_id_int'));
      expect(getOperation['x-route-name'], equals('users.show'));

      final parameters = getOperation['parameters'] as List<Object?>;
      final idParameter = parameters.first as Map<String, Object?>;
      expect(idParameter['name'], equals('id'));
      expect(idParameter['in'], equals('path'));
      final schema = idParameter['schema'] as Map<String, Object?>;
      expect(schema['type'], equals('integer'));

      final responses = getOperation['responses'] as Map<String, Object?>;
      expect(responses, contains('200'));
      final okResponse = responses['200'] as Map<String, Object?>;
      expect(okResponse['description'], equals('User found'));
      final content = okResponse['content'] as Map<String, Object?>;
      expect(content, contains('application/json'));
    });

    test('populates defaults when metadata is absent', () {
      final manifest = RouteManifest(
        routes: [RouteManifestEntry(method: 'POST', path: '/sessions')],
      );

      final document = generateOpenApiDocument(
        manifest,
        info: const OpenApiDocumentInfo(title: 'Demo', version: '1.0.0'),
      );

      final paths = document['paths'] as Map<String, Object?>;
      final sessionPath = paths['/sessions'] as Map<String, Object?>;
      final postOperation = sessionPath['post'] as Map<String, Object?>;

      expect(postOperation['summary'], equals('POST /sessions'));
      expect(postOperation['tags'], equals(['sessions']));
      expect(postOperation['operationId'], equals('post_sessions'));

      final responses = postOperation['responses'] as Map<String, Object?>;
      expect(responses['200'], isA<Map<String, Object?>>());
    });
  });

  group('RouteBuilder.openApi', () {
    test('stores metadata in constraints', () {
      final router = Router();
      router.get('/hello/{name}', (ctx) => ctx.string('hello')).openApi((
        operation,
      ) {
        operation.summary = 'Say hello';
        operation.parameter(
          name: 'name',
          location: 'path',
          required: true,
          schema: {'type': 'string'},
        );
      });

      final route = router.routes.first;
      expect(route.constraints, contains('openapi'));
      final metadata = route.constraints['openapi'] as Map<String, Object?>;
      expect(metadata['summary'], equals('Say hello'));
      final parameters = metadata['parameters'] as List<Object?>;
      expect(parameters.length, equals(1));
      final parameter = parameters.first as Map<String, Object?>;
      expect(parameter['name'], equals('name'));
    });
  });

  group('complex route shapes', () {
    test('handles groups, wildcards, and optional parameters', () async {
      final engine = await Engine.create();
      engine.group(
        path: '/api',
        builder: (api) {
          api.group(
            path: '/v1',
            builder: (v1) {
              v1
                  .get(
                    '/users/{id:int}/{section?}',
                    (ctx) async => ctx.json({'ok': true}),
                  )
                  .name('users.section')
                  .constraints({'visibility': 'public'})
                  .openApi((operation) {
                    operation.summary = 'Fetch user section';
                    operation.tags(['users', 'v1']);
                    operation.jsonResponse(
                      status: '200',
                      description: 'User payload',
                      schema: {
                        'type': 'object',
                        'properties': {
                          'ok': {'type': 'boolean'},
                        },
                      },
                    );
                  });

              v1
                  .get(
                    '/files/{path:*}',
                    (ctx) async => ctx.json({'file': 'ok'}),
                  )
                  .openApi(
                    (operation) => operation.jsonResponse(
                      status: '200',
                      description: 'File descriptor',
                    ),
                  );
            },
          );
        },
      );
      final manifest = engine.buildRouteManifest();
      final document = generateOpenApiDocument(
        manifest,
        info: const OpenApiDocumentInfo(title: 'Complex API', version: '1.0.0'),
      );

      await engine.close();

      final paths = document['paths'] as Map<String, Object?>;
      expect(paths, contains('/api/v1/users/{id:int}/{section?}'));
      expect(paths, contains('/api/v1/files/{path:*}'));

      final userOperations =
          paths['/api/v1/users/{id:int}/{section?}'] as Map<String, Object?>;
      final userGet = userOperations['get'] as Map<String, Object?>;
      expect(userGet['summary'], equals('Fetch user section'));
      expect(userGet['tags'], equals(['users', 'v1']));
      expect(userGet['x-route-name'], equals('users.section'));

      final userParameters = (userGet['parameters'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final idParam = userParameters.firstWhere(
        (param) => param['name'] == 'id',
      );
      expect(idParam['required'], isTrue);
      final idSchema = idParam['schema'] as Map<String, Object?>;
      expect(idSchema['type'], equals('integer'));

      final sectionParam = userParameters.firstWhere(
        (param) => param['name'] == 'section',
      );
      expect(sectionParam['required'], isFalse);
      final sectionSchema = sectionParam['schema'] as Map<String, Object?>;
      expect(sectionSchema['type'], equals('string'));

      final fileOperations =
          paths['/api/v1/files/{path:*}'] as Map<String, Object?>;
      final fileGet = fileOperations['get'] as Map<String, Object?>;
      final fileParams = (fileGet['parameters'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final pathParam = fileParams.firstWhere(
        (param) => param['name'] == 'path',
      );
      expect(pathParam['required'], isTrue);
      final pathSchema = pathParam['schema'] as Map<String, Object?>;
      expect(pathSchema['type'], equals('string'));
    });
  });
}
