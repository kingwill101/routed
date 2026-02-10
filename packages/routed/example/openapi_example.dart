/// Example: OpenAPI schema generation with routed.
///
/// This example demonstrates how to attach [RouteSchema] metadata to routes
/// and generate an OpenAPI 3.1 specification at runtime. The same metadata
/// is also used by:
///
/// - **Auto-validation**: requests are validated against `validationRules`
///   before reaching the handler.
/// - **Build-runner**: `dart run build_runner build` generates `openapi.json`
///   and a serving controller (after running `dart run routed spec`).
///
/// ## Quick start
///
/// ```bash
/// dart run example/openapi_example.dart
/// ```
///
/// Then visit:
/// - `GET /openapi.json` — the generated OpenAPI spec
/// - `GET /api/users` — list users
/// - `POST /api/users` — create a user (auto-validated)
/// - `GET /api/users/:id` — get a user by ID
/// - `DELETE /api/users/:id` — delete a user (deprecated)
///
/// ## Build-runner workflow
///
/// For projects that use `build_runner`, the same schemas produce a static
/// `openapi.json` file:
///
/// ```bash
/// # 1. Generate route manifest
/// dart run routed spec
///
/// # 2. Run the builder (opt-in via build.yaml)
/// dart run build_runner build
///
/// # 3. Output: lib/generated/openapi.json
/// #           lib/generated/openapi_controller.g.dart
/// ```
///
/// Configure the builder in your project's `build.yaml`:
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       routed|openapi:
///         options:
///           title: "User Service"
///           version: "1.0.0"
///           description: "User management API"
///           servers:
///             - url: "https://api.example.com"
/// ```
import 'dart:convert';

import 'package:routed/routed.dart';

// ---------------------------------------------------------------------------
// Domain model
// ---------------------------------------------------------------------------

class User {
  User({required this.id, required this.name, required this.email, this.age});

  final int id;
  final String name;
  final String email;
  final int? age;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    if (age != null) 'age': age,
  };
}

class UserRepository {
  int _nextId = 3;
  final Map<String, User> _users = {
    '1': User(id: 1, name: 'Alice', email: 'alice@example.com', age: 30),
    '2': User(id: 2, name: 'Bob', email: 'bob@example.com'),
  };

  List<User> all() => _users.values.toList();
  User? find(String id) => _users[id];

  User create({required String name, required String email, int? age}) {
    final id = (_nextId++).toString();
    final user = User(id: int.parse(id), name: name, email: email, age: age);
    _users[id] = user;
    return user;
  }

  bool remove(String id) => _users.remove(id) != null;
}

// ---------------------------------------------------------------------------
// App factory
// ---------------------------------------------------------------------------

/// Creates an engine with OpenAPI-documented routes.
///
/// Every route carries a [RouteSchema] that describes its parameters,
/// request body, and responses. This metadata is used for:
/// 1. Runtime request validation (via `validationRules`)
/// 2. OpenAPI spec generation (via the builder or the `/openapi.json` endpoint)
Engine createOpenApiApp({UserRepository? repository}) {
  final repo = repository ?? UserRepository();
  final engine = Engine();

  // -- List users ----------------------------------------------------------
  engine.get(
    '/api/users',
    (EngineContext ctx) {
      return ctx.json({'users': repo.all().map((u) => u.toJson()).toList()});
    },
    schema: const RouteSchema(
      summary: 'List all users',
      description: 'Returns a JSON array of all registered users.',
      tags: ['users'],
      operationId: 'listUsers',
      responses: [
        ResponseSchema(
          200,
          description: 'A list of users',
          contentType: 'application/json',
          jsonSchema: {
            'type': 'object',
            'properties': {
              'users': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'integer'},
                    'name': {'type': 'string'},
                    'email': {'type': 'string', 'format': 'email'},
                    'age': {'type': 'integer'},
                  },
                },
              },
            },
          },
        ),
      ],
    ),
  );

  // -- Create user ---------------------------------------------------------
  //
  // Uses `validationRules` for both auto-validation AND schema generation.
  // Invalid requests are rejected with 422 before the handler runs.
  engine.post(
    '/api/users',
    (EngineContext ctx) async {
      final body = jsonDecode(await ctx.request.body()) as Map<String, dynamic>;
      final user = repo.create(
        name: body['name'] as String,
        email: body['email'] as String,
        age: body['age'] as int?,
      );
      return ctx.json(user.toJson(), statusCode: HttpStatus.created);
    },
    schema: const RouteSchema(
      summary: 'Create a new user',
      description:
          'Creates a user with the given name and email. '
          'The request body is auto-validated against the validation rules.',
      tags: ['users'],
      operationId: 'createUser',
      validationRules: {
        'name': 'required|string|min:2|max:100',
        'email': 'required|email',
        'age': 'integer|min:0|max:150',
      },
      responses: [
        ResponseSchema(
          201,
          description: 'User created successfully',
          contentType: 'application/json',
          jsonSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'name': {'type': 'string'},
              'email': {'type': 'string'},
            },
          },
        ),
        ResponseSchema(422, description: 'Validation failed'),
      ],
    ),
  );

  // -- Get user by ID ------------------------------------------------------
  engine.get(
    '/api/users/:id',
    (EngineContext ctx) {
      final id = ctx.param('id');
      final user = id != null ? repo.find(id) : null;
      if (user == null) {
        return ctx.json({
          'error': 'User not found',
        }, statusCode: HttpStatus.notFound);
      }
      return ctx.json(user.toJson());
    },
    schema: RouteSchema(
      summary: 'Get a user by ID',
      tags: const ['users'],
      operationId: 'getUser',
      params: [
        const ParamSchema(
          'id',
          location: ParamLocation.path,
          description: 'The user\'s numeric ID',
          jsonSchema: {'type': 'integer'},
          example: 1,
        ),
      ],
      responses: const [
        ResponseSchema(200, description: 'The user object'),
        ResponseSchema(404, description: 'User not found'),
      ],
    ),
  );

  // -- Delete user (deprecated) --------------------------------------------
  engine.delete(
    '/api/users/:id',
    (EngineContext ctx) {
      final id = ctx.param('id');
      if (id == null || !repo.remove(id)) {
        return ctx.json({
          'error': 'User not found',
        }, statusCode: HttpStatus.notFound);
      }
      return ctx.json({'status': 'deleted'});
    },
    schema: RouteSchema(
      summary: 'Delete a user',
      description:
          'Deprecated: use PATCH /api/users/:id with '
          '{"active": false} instead.',
      tags: const ['users'],
      operationId: 'deleteUser',
      deprecated: true,
      params: [
        const ParamSchema(
          'id',
          location: ParamLocation.path,
          description: 'The user\'s numeric ID',
          jsonSchema: {'type': 'integer'},
        ),
      ],
      responses: const [
        ResponseSchema(200, description: 'User deleted'),
        ResponseSchema(404, description: 'User not found'),
      ],
    ),
  );

  // -- Health check (hidden from spec) -------------------------------------
  engine.get(
    '/health',
    (EngineContext ctx) => ctx.json({'status': 'ok'}),
    schema: const RouteSchema(hidden: true),
  );

  // -- Serve OpenAPI spec at runtime ---------------------------------------
  //
  // This generates the spec on the fly from the engine's route manifest.
  // For production, prefer the build_runner approach which generates a
  // static file.
  engine.get('/openapi.json', (EngineContext ctx) {
    final manifest = engine.buildRouteManifest();
    final spec = manifestToOpenApi(
      manifest,
      config: const OpenApiConfig(
        title: 'User Service',
        version: '1.0.0',
        description: 'Example API demonstrating OpenAPI generation with routed',
        servers: [OpenApiServer(url: 'http://localhost:3000')],
      ),
    );
    ctx.response.headers.set('Content-Type', 'application/json; charset=utf-8');
    return ctx.string(spec.toJsonString(pretty: true));
  });

  return engine;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final engine = createOpenApiApp();
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 3000 : 3000;
  print('OpenAPI example listening on http://localhost:$port');
  print('  GET  /openapi.json        — OpenAPI 3.1 spec');
  print('  GET  /api/users           — list users');
  print('  POST /api/users           — create user (auto-validated)');
  print('  GET  /api/users/:id       — get user');
  print('  DELETE /api/users/:id     — delete user (deprecated)');
  await engine.serve(port: port);
}
