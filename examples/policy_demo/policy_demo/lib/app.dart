import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart' hide Event;
import 'package:server_auth_ormed/server_auth_ormed.dart';

import 'migrations.dart';

class Project {
  const Project({required this.id, required this.name, required this.ownerId});

  factory Project.fromRow(AdHocRow row) => Project(
    id: row['id']!.toString(),
    name: row['name']!.toString(),
    ownerId: row['owner_id']!.toString(),
  );

  final String id;
  final String name;
  final String ownerId;

  Project copyWith({String? name, String? ownerId}) {
    return Project(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ownerId': ownerId};
}

const _projectColumns = <AdHocColumn>[
  AdHocColumn(
    name: 'id',
    dartType: 'int',
    columnType: 'INTEGER',
    isNullable: false,
    isPrimaryKey: true,
  ),
  AdHocColumn(name: 'name', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'owner_id', dartType: 'String', isNullable: false),
];

Query<AdHocRow> _projects(OrmDatabase database) =>
    database.table('projects', columns: _projectColumns);

class ProjectPolicy extends Policy<Project> {
  const ProjectPolicy();

  @override
  Future<bool> canView(AuthPrincipal? principal, Project resource) async {
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.id == resource.ownerId;
  }

  @override
  Future<bool> canCreate(AuthPrincipal? principal) async {
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.hasRole('editor');
  }

  @override
  Future<bool> canUpdate(AuthPrincipal? principal, Project resource) async {
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.id == resource.ownerId;
  }

  @override
  Future<bool> canDelete(AuthPrincipal? principal, Project resource) async {
    if (principal == null) return false;
    return principal.hasRole('admin');
  }
}

Future<Engine> createEngine({
  String databasePath = 'storage/policy_demo.sqlite',
}) async {
  registerRoutedProviders();
  if (databasePath != ':memory:') {
    File(databasePath).absolute.parent.createSync(recursive: true);
  }
  final database = await SqliteDatabase.connect(path: databasePath);
  final schema = const OrmAuthSchema(tablePrefix: 'policy_demo');
  final authStore = OrmAuthStore(database, schema: schema);
  final databases = DatabaseManager()..register('default', database);
  final engine = Engine(
    providers: [
      RoutedDatabaseProvider(
        manager: databases,
        migrations: [...schema.migrations, ...appMigrations],
        migrateOnBoot: true,
      ),
      RoutedSessionsProvider(
        SessionConfig.cookie(
          cookieName: 'policy_session',
          options: SessionOptions(
            path: '/',
            secure: false,
            httpOnly: true,
            sameSite: SameSite.lax,
          ),
        ),
      ),
      ...Engine.builtins,
    ],
  );

  final policyBindings = [
    PolicyBinding<Project>(
      policy: const ProjectPolicy(),
      abilityPrefix: 'project',
    ),
  ];

  final authOptions = AuthOptions<EngineContext>(
    providers: [CredentialsProvider()],
    store: authStore,
    storeMode: AuthStoreMode.durable,
    runtimeMode: AuthRuntimeMode.localDevelopment,
    policies: PolicyOptions(bindings: policyBindings),
  );
  engine.container.instance<AuthOptions>(authOptions);
  registerPoliciesWithHaigate(policyBindings);
  engine.addGlobalMiddleware(sessionMiddleware());
  late final AuthManager authManager;
  await engine.initialize();

  await _seedUsers(authStore);
  authManager = AuthManager(authOptions, sessionAuth: SessionAuth.instance);
  engine.container.instance<AuthManager>(authManager);
  await _seedProjects(database);

  engine.group(
    path: '/api/v1',
    builder: (router) {
      router.get('/health', (ctx) async {
        return ctx.json({'status': 'ok'});
      });

      router.get('/csrf', (ctx) async {
        final cookieName = ctx.engineConfig.security.csrfCookieName;
        var token = ctx.getSession<String>(cookieName) ?? '';
        if (token.isEmpty) {
          token = _generateCsrfToken();
          ctx.setSession(cookieName, token);
          ctx.setCookie(
            cookieName,
            token,
            httpOnly: true,
            secure: false,
            sameSite: SameSite.lax,
            maxAge: const Duration(hours: 1).inSeconds,
          );
        }
        return ctx.json({'csrfToken': token});
      });

      router.post('/login', (ctx) async {
        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final id = payload['id']?.toString() ?? 'viewer';
        final user = await authStore.users.findById(id);
        if (user == null) {
          return ctx.json({'error': 'invalid_credentials'}, statusCode: 401);
        }
        final manager = authManager;
        final provider = manager.runtime.providers
            .whereType<CredentialsProvider>()
            .first;
        try {
          final result = await manager.signInWithCredentials(
            ctx,
            provider,
            AuthCredentials(email: user.email, password: 'password123'),
          );
          return ctx.json({
            'status': 'ok',
            'principal': result.session.user.toPrincipal().toJson(),
          });
        } on AuthFlowException {
          return ctx.json({'error': 'invalid_credentials'}, statusCode: 401);
        }
      });

      router.get('/me', (ctx) async {
        final principal = SessionAuth.current(ctx);
        return ctx.json({'principal': principal?.toJson()});
      });

      router.get('/projects', (ctx) async {
        final visible = <Map<String, dynamic>>[];
        final rows = await _projects(ctx.db()).orderBy('id').get();
        for (final row in rows) {
          final project = Project.fromRow(row);
          final allowed = await Haigate.can(
            'project.view',
            ctx: ctx,
            payload: project,
          );
          if (allowed) {
            visible.add(project.toJson());
          }
        }
        return ctx.json({'data': visible});
      });

      router.post('/projects', (ctx) async {
        try {
          await Haigate.authorize('project.create', ctx: ctx);
        } on GateViolation {
          return ctx.json({
            'error': 'forbidden',
          }, statusCode: HttpStatus.forbidden);
        }

        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final principal = SessionAuth.current(ctx);
        final latest = await _projects(
          ctx.db(),
        ).orderBy('id', descending: true).limit(1).get();
        final id = (latest.isEmpty ? 0 : latest.first['id'] as int) + 1;
        final created = Project(
          id: id.toString(),
          name: payload['name']?.toString() ?? 'project-$id',
          ownerId: principal?.id ?? 'system',
        );
        await _projects(ctx.db()).insertManyInputs([
          {'id': id, 'name': created.name, 'owner_id': created.ownerId},
        ], returning: false);
        return ctx.json(created.toJson(), statusCode: HttpStatus.created);
      });

      router.get('/projects/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final projectId = int.tryParse(id);
        final project = await ctx.fetchOr404(
          () async => projectId == null
              ? null
              : (await _projects(ctx.db()).whereEquals('id', projectId).get())
                    .map(Project.fromRow)
                    .firstOrNull,
          message: 'Project not found',
        );
        try {
          await Haigate.authorize('project.view', ctx: ctx, payload: project);
        } on GateViolation {
          return ctx.json({
            'error': 'forbidden',
          }, statusCode: HttpStatus.forbidden);
        }
        return ctx.json(project.toJson());
      });

      router.put('/projects/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final projectId = int.tryParse(id);
        final project = await ctx.fetchOr404(
          () async => projectId == null
              ? null
              : (await _projects(ctx.db()).whereEquals('id', projectId).get())
                    .map(Project.fromRow)
                    .firstOrNull,
          message: 'Project not found',
        );
        try {
          await Haigate.authorize('project.update', ctx: ctx, payload: project);
        } on GateViolation {
          return ctx.json({
            'error': 'forbidden',
          }, statusCode: HttpStatus.forbidden);
        }

        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final updated = project.copyWith(name: payload['name']?.toString());
        await _projects(
          ctx.db(),
        ).whereEquals('id', projectId).update({'name': updated.name});
        return ctx.json(updated.toJson());
      });

      router.get('/users', (ctx) async {
        final users = await authStore.listUsersForAdministration();
        return ctx.json({
          'data': users
              .map(
                (user) => {
                  'id': user.id,
                  'name': user.name,
                  'email': user.email,
                },
              )
              .toList(),
        });
      });

      router.get('/users/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final user = await ctx.fetchOr404(
          () async => authStore.users.findById(id),
          message: 'User not found',
        );
        return ctx.json({
          'id': user.id,
          'name': user.name,
          'email': user.email,
        });
      });

      router.post('/users', (ctx) async {
        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        final users = await authStore.listUsersForAdministration();
        final id = (users.length + 1).toString();
        final created = AuthUser(
          id: id,
          name: payload['name']?.toString() ?? 'user-$id',
          email: payload['email']?.toString() ?? 'user$id@example.com',
        );
        await authStore.users.create(created);
        return ctx.json({
          'id': created.id,
          'name': created.name,
          'email': created.email,
        }, statusCode: HttpStatus.created);
      });
    },
  );

  return engine;
}

Future<void> _seedProjects(OrmDatabase database) async {
  final existing = await _projects(database).get();
  if (existing.isNotEmpty) return;
  await _projects(database).insertManyInputs([
    {'id': 1, 'name': 'Compiler', 'owner_id': 'ada'},
    {'id': 2, 'name': 'Machine', 'owner_id': 'alan'},
  ], returning: false);
}

Future<void> _seedUsers(OrmAuthStore store) async {
  final hasher = Argon2idPasswordHasher(
    iterations: 1,
    memoryKiB: 8,
    derivedKeyLength: 16,
  );
  final now = DateTime.now().toUtc();
  for (final user in <AuthUser>[
    AuthUser(id: '1', name: 'Ada Lovelace', email: 'ada-legacy@example.com'),
    AuthUser(id: '2', name: 'Alan Turing', email: 'alan-legacy@example.com'),
    AuthUser(
      id: 'ada',
      name: 'Ada Lovelace',
      email: 'ada@example.com',
      roles: ['editor'],
    ),
    AuthUser(
      id: 'alan',
      name: 'Alan Turing',
      email: 'alan@example.com',
      roles: ['viewer'],
    ),
  ]) {
    if (await store.users.findById(user.id) != null) continue;
    await store.credentials.register(
      user,
      AuthPasswordCredential(
        id: 'credential-${user.id}',
        userId: user.id,
        identifier: user.email!,
        passwordHash: hasher.hash('password123'),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

String _generateCsrfToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64UrlEncode(bytes);
}
