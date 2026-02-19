/// OpenAPI Demo — a scaffolded Routed API with full OpenAPI 3.1 support.
///
/// This example demonstrates three ways to use the OpenAPI system:
///
/// 1. **Runtime spec generation** — visit `GET /openapi.json` to get the
///    OpenAPI spec generated on the fly from route metadata.
///
/// 2. **Auto-validation** — `POST /api/v1/users` validates request bodies
///    against `validationRules` before the handler runs. Invalid requests
///    get a 422 response automatically.
///
/// 3. **Build-runner** (static generation) — run the two-step pipeline:
///    ```bash
///    dart run routed spec                  # writes route_manifest.json
///    dart run build_runner build           # generates openapi.json + controller
///    ```
///
/// ## Quick start
///
/// ```bash
/// cd examples/openapi_demo
/// dart run routed dev
/// ```
///
/// Then try:
/// - `GET  /openapi.json`            — OpenAPI 3.1 spec
/// - `GET  /api/v1/health`           — health check (hidden from spec)
/// - `GET  /api/v1/users`            — list users
/// - `POST /api/v1/users`            — create user (auto-validated)
/// - `GET  /api/v1/users/{id}`       — get user by ID
/// - `DELETE /api/v1/users/{id}`     — delete user (deprecated)
library;

import 'dart:isolate';
import 'dart:io' as io;

import 'package:routed/routed.dart';
import 'package:openapi_demo/metadata_routes.dart';

Future<Engine> createEngine({bool initialize = true}) async {
  final engine = Engine(
    providers: [
      CoreServiceProvider.withLoader(
        const ConfigLoaderOptions(
          configDirectory: 'config',
          loadEnvFiles: false,
          includeEnvironmentSubdirectory: false,
        ),
      ),
      RoutingServiceProvider(),
    ],
  );

  if (initialize) {
    await engine.initialize();
  }

  // -------------------------------------------------------------------------
  // In-memory data store
  // -------------------------------------------------------------------------

  final users = <String, Map<String, dynamic>>{
    '1': {'id': '1', 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    '2': {'id': '2', 'name': 'Alan Turing', 'email': 'alan@example.com'},
  };

  // -------------------------------------------------------------------------
  // API routes — each carries a RouteSchema describing its contract
  // -------------------------------------------------------------------------

  engine.group(
    path: '/api/v1',
    builder: (router) {
      // -- Health check (hidden from OpenAPI spec) --------------------------
      router.get(
        '/health',
        (ctx) async => ctx.json({'status': 'ok'}),
        schema: const RouteSchema(hidden: true),
      );

      // -- List users -------------------------------------------------------
      router.get(
        '/users',
        (ctx) async => ctx.json({'data': users.values.toList()}),
        schema: const RouteSchema(
          summary: 'List all users',
          description:
              'Returns a paginated list of all registered users. '
              'Currently returns all users without pagination.',
          tags: ['Users'],
          operationId: 'listUsers',
          responses: [
            ResponseSchema(
              200,
              description: 'A list of user objects',
              contentType: 'application/json',
              jsonSchema: {
                'type': 'object',
                'properties': {
                  'data': {
                    'type': 'array',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'id': {'type': 'string'},
                        'name': {'type': 'string'},
                        'email': {'type': 'string', 'format': 'email'},
                      },
                    },
                  },
                },
              },
            ),
          ],
        ),
      );

      // -- Get user by ID ---------------------------------------------------
      router.get(
        '/users/{id}',
        (ctx) async {
          final id = ctx.mustGetParam<String>('id');
          final user = await ctx.fetchOr404(
            () async => users[id],
            message: 'User not found',
          );
          return ctx.json(user);
        },
        schema: const RouteSchema(
          summary: 'Get a user by ID',
          tags: ['Users'],
          operationId: 'getUser',
          params: [
            ParamSchema(
              'id',
              location: ParamLocation.path,
              description: 'The unique user identifier',
              jsonSchema: {'type': 'string'},
            ),
          ],
          responses: [
            ResponseSchema(
              200,
              description: 'The user object',
              contentType: 'application/json',
              jsonSchema: {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'name': {'type': 'string'},
                  'email': {'type': 'string', 'format': 'email'},
                },
              },
            ),
            ResponseSchema(404, description: 'User not found'),
          ],
        ),
      );

      // -- Create user (with auto-validation) -------------------------------
      //
      // The `validationRules` are used for two things:
      //   1. Auto-validation middleware: invalid requests → 422 before handler
      //   2. OpenAPI schema: rules are converted to JSON Schema in the spec
      router.post(
        '/users',
        (ctx) async {
          final payload = Map<String, dynamic>.from(
            await ctx.bindJSON({}) as Map? ?? const {},
          );
          final id = (users.length + 1).toString();
          final created = {
            'id': id,
            'name': payload['name'] ?? 'user-$id',
            'email': payload['email'] ?? 'user$id@example.com',
          };
          users[id] = created;
          return ctx.json(created, statusCode: HttpStatus.created);
        },
        schema: const RouteSchema(
          summary: 'Create a new user',
          description:
              'Creates a user with the given name and email. '
              'The request body is automatically validated against the '
              'defined validation rules before reaching the handler.',
          tags: ['Users'],
          operationId: 'createUser',
          validationRules: {
            'name': 'required|string|min:2|max:100',
            'email': 'required|email',
          },
          responses: [
            ResponseSchema(
              201,
              description: 'User created successfully',
              contentType: 'application/json',
              jsonSchema: {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'name': {'type': 'string'},
                  'email': {'type': 'string'},
                },
              },
            ),
            ResponseSchema(422, description: 'Validation failed'),
          ],
        ),
      );

      // -- Delete user (deprecated) -----------------------------------------
      router.delete(
        '/users/{id}',
        (ctx) async {
          final id = ctx.mustGetParam<String>('id');
          if (users.remove(id) == null) {
            return ctx.json({
              'error': 'User not found',
            }, statusCode: HttpStatus.notFound);
          }
          return ctx.json({'status': 'deleted'});
        },
        schema: const RouteSchema(
          summary: 'Delete a user',
          description:
              'Deprecated: prefer PATCH /api/v1/users/{id} with '
              '{"active": false} instead.',
          tags: ['Users'],
          operationId: 'deleteUser',
          deprecated: true,
          params: [
            ParamSchema(
              'id',
              location: ParamLocation.path,
              description: 'The unique user identifier',
              jsonSchema: {'type': 'string'},
            ),
          ],
          responses: [
            ResponseSchema(200, description: 'User deleted'),
            ResponseSchema(404, description: 'User not found'),
          ],
        ),
      );

      // -- Metadata merger demo routes (cross-file + nested groups) ----------
      registerMetadataRoutes(router);
    },
  );

  // -------------------------------------------------------------------------
  // Runtime OpenAPI spec endpoint
  // -------------------------------------------------------------------------
  //
  // Generates the spec on the fly from the engine's route manifest. For
  // production use, prefer the build_runner approach which outputs a static
  // openapi.json file.

  final projectRoot = await _resolveProjectRoot();
  engine.get('/openapi.json', (ctx) async {
    final manifest = engine.buildRouteManifest();
    final enrichedManifest = await enrichManifestWithProjectMetadata(
      manifest,
      projectRoot: projectRoot,
      packageName: 'openapi_demo',
    );
    final spec = manifestToOpenApi(
      enrichedManifest,
      config: const OpenApiConfig(
        title: 'OpenAPI Demo',
        version: '1.0.0',
        description:
            'A demonstration API showing OpenAPI 3.1 spec generation '
            'with the routed framework.',
        servers: [OpenApiServer(url: 'http://localhost:8080')],
      ),
    );
    ctx.response.headers.set('Content-Type', 'application/json; charset=utf-8');
    return ctx.string(spec.toJsonString(pretty: true));
  });

  return engine;
}

Future<String> _resolveProjectRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:openapi_demo/app.dart'),
  );
  if (uri != null && uri.scheme == 'file') {
    final appFile = io.File.fromUri(uri);
    final libDir = appFile.parent;
    return libDir.parent.path;
  }
  return io.Directory.current.path;
}
