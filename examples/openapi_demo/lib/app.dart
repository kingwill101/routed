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
///    dart run routed_cli openapi generate       # writes route_manifest.json
///    dart run build_runner build           # generates openapi.json + controller
///    ```
///
/// ## Quick start
///
/// ```bash
/// cd examples/openapi_demo
/// dart run routed_cli dev
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

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';
import 'package:openapi_demo/metadata_routes.dart';

import 'migrations.dart';

const _userColumns = <AdHocColumn>[
  AdHocColumn(
    name: 'id',
    dartType: 'int',
    columnType: 'INTEGER',
    isNullable: false,
    isPrimaryKey: true,
  ),
  AdHocColumn(name: 'name', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'email', dartType: 'String', isNullable: false),
];

Future<Engine> createEngine({
  String databasePath = 'storage/openapi_demo.sqlite',
  bool initialize = true,
}) async {
  if (databasePath != ':memory:') {
    io.File(databasePath).absolute.parent.createSync(recursive: true);
  }
  final database = await SqliteDatabase.connect(path: databasePath);
  final databases = DatabaseManager()..register('default', database);
  final engine = Engine(
    providers: [
      RoutedDatabaseProvider(
        manager: databases,
        migrations: appMigrations,
        migrateOnBoot: true,
      ),
      ...Engine.defaultProviders,
    ],
  );

  if (initialize) {
    await engine.initialize();
    await _seedUsers(database);
  }

  // -------------------------------------------------------------------------
  // API routes — each carries a RouteSchema describing its contract
  // -------------------------------------------------------------------------

  engine.group(
    path: '/api/v1',
    builder: (router) {
      // -- Health check (hidden from OpenAPI spec) --------------------------
      router.get('/health', (ctx) async => ctx.json({'status': 'ok'})).hidden();

      // -- List users -------------------------------------------------------
      router
          .get(
            '/users',
            (ctx) async => ctx.json({'data': await _listUsers(ctx.db())}),
          )
          .summary('List all users')
          .description(
            'Returns a paginated list of all registered users. Currently returns all registered users.',
          )
          .tags(['Users'])
          .operationId('listUsers')
          .responseSchema(
            const ResponseSchema(200, description: 'A list of user objects'),
          );

      // -- Get user by ID ---------------------------------------------------
      router
          .get('/users/{id}', (ctx) async {
            final id = ctx.mustGetParam<String>('id');
            final user = await ctx.fetchOr404(
              () async => _findUser(ctx.db(), int.tryParse(id)),
              message: 'User not found',
            );
            return ctx.json(user);
          })
          .summary('Get a user by ID')
          .tags(['Users'])
          .operationId('getUser')
          .responseSchema(
            const ResponseSchema(200, description: 'The user object'),
          )
          .responseSchema(
            const ResponseSchema(404, description: 'User not found'),
          );

      // -- Create user (with auto-validation) -------------------------------
      //
      // The fluent metadata is the runtime source of truth for the route.
      router
          .post('/users', (ctx) async {
            final payload = Map<String, dynamic>.from(
              await ctx.bindJSON({}) as Map? ?? const {},
            );
            final latest = await _users(
              ctx.db(),
            ).orderBy('id', descending: true).limit(1).get();
            final id = ((latest.isEmpty ? 0 : latest.first['id'] as int) + 1)
                .toString();
            final created = {
              'id': id,
              'name': payload['name'] ?? 'user-$id',
              'email': payload['email'] ?? 'user$id@example.com',
            };
            await _users(ctx.db()).insertManyInputs([
              {
                'id': int.parse(id),
                'name': created['name'],
                'email': created['email'],
              },
            ], returning: false);
            return ctx.json(created, statusCode: HttpStatus.created);
          })
          .summary('Create a new user')
          .description('Creates a user with the given name and email.')
          .tags(['Users'])
          .operationId('createUser')
          .responseSchema(
            const ResponseSchema(201, description: 'User created successfully'),
          )
          .responseSchema(
            const ResponseSchema(422, description: 'Validation failed'),
          );

      // -- Delete user (deprecated) -----------------------------------------
      router
          .delete('/users/{id}', (ctx) async {
            final id = ctx.mustGetParam<String>('id');
            final userId = int.tryParse(id);
            final deleted = userId == null
                ? 0
                : await _users(ctx.db()).whereEquals('id', userId).delete();
            if (deleted == 0) {
              return ctx.json({
                'error': 'User not found',
              }, statusCode: HttpStatus.notFound);
            }
            return ctx.json({'status': 'deleted'});
          })
          .summary('Delete a user')
          .description(
            'Deprecated: prefer PATCH /api/v1/users/{id} with {"active": false} instead.',
          )
          .tags(['Users'])
          .operationId('deleteUser')
          .deprecated()
          .responseSchema(
            const ResponseSchema(200, description: 'User deleted'),
          )
          .responseSchema(
            const ResponseSchema(404, description: 'User not found'),
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

Query<AdHocRow> _users(OrmDatabase database) =>
    database.table('users', columns: _userColumns);

Future<List<Map<String, dynamic>>> _listUsers(OrmDatabase database) async {
  final rows = await _users(database).orderBy('id').get();
  return rows.map(_userJson).toList();
}

Future<Map<String, dynamic>?> _findUser(OrmDatabase database, int? id) async {
  if (id == null) return null;
  final rows = await _users(database).whereEquals('id', id).limit(1).get();
  return rows.isEmpty ? null : _userJson(rows.first);
}

Map<String, dynamic> _userJson(AdHocRow row) => {
  'id': row['id'].toString(),
  'name': row['name'],
  'email': row['email'],
};

Future<void> _seedUsers(OrmDatabase database) async {
  if ((await _users(database).limit(1).get()).isNotEmpty) return;
  await _users(database).insertManyInputs([
    {'id': 1, 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    {'id': 2, 'name': 'Alan Turing', 'email': 'alan@example.com'},
  ], returning: false);
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
