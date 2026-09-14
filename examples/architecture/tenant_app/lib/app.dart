import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';

import 'migrations.dart';

const _appKey =
    'base64:MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Ng==';

const aliceId = 'user-alice';
const bobId = 'user-bob';
const acmeId = 'tenant-acme';
const betaId = 'tenant-beta';

const _projectColumns = <AdHocColumn>[
  AdHocColumn(
    name: 'id',
    dartType: 'int',
    columnType: 'INTEGER',
    isNullable: false,
    isPrimaryKey: true,
  ),
  AdHocColumn(name: 'tenant_id', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'owner_id', dartType: 'String', isNullable: false),
  AdHocColumn(name: 'name', dartType: 'String', isNullable: false),
];

Argon2idPasswordHasher _demoPasswordHasher() =>
    Argon2idPasswordHasher(iterations: 1, memoryKiB: 8, derivedKeyLength: 16);

/// Builds the local multi-tenant reference application.
Future<Engine> createEngine({String databasePath = ':memory:'}) async {
  if (databasePath != ':memory:') {
    File(databasePath).absolute.parent.createSync(recursive: true);
  }
  final database = await SqliteDatabase.connect(path: databasePath);
  final authSchema = const OrmAuthSchema();
  final organizationSchema = const OrmAuthOrganizationSchema();
  final authStore = OrmAuthStore(database, schema: authSchema);
  final organizationStore = OrmAuthOrganizationStore(
    database,
    schema: organizationSchema,
  );
  final rememberStore = OrmRememberTokenStore(database, schema: authSchema);
  final organizations = OrganizationPlugin<EngineContext>(
    store: organizationStore,
    options: AuthOrganizationOptions<EngineContext>(
      staticRoles: <String, AuthOrganizationPermissionSet>{
        'owner': <String, Iterable<String>>{
          'organization': <String>['create', 'read', 'update', 'delete'],
          'member': <String>['create', 'read', 'update', 'delete'],
          'invitation': <String>['create', 'read', 'cancel'],
          'role': <String>['create', 'read', 'update', 'delete'],
          'team': <String>['create', 'read', 'update', 'delete'],
          'team-member': <String>['create', 'read', 'delete'],
          'projects': <String>['read', 'create', 'update', 'delete'],
        },
        'member': <String, Iterable<String>>{
          'organization': <String>['read'],
          'member': <String>['read'],
          'invitation': <String>['read'],
          'role': <String>['read'],
          'team': <String>['read'],
          'team-member': <String>['read'],
          'projects': <String>['read'],
        },
      },
    ),
  );
  final databases = DatabaseManager()..register('default', database);
  final sessionAuth = SessionAuth.configure(
    rememberStore: rememberStore,
    rememberCookieName: 'tenant_example_remember',
  );
  final authManager = AuthManager(
    AuthOptions<EngineContext>(
      providers: <AuthProvider>[CredentialsProvider()],
      store: authStore,
      storeMode: AuthStoreMode.durable,
      runtimeMode: AuthRuntimeMode.localDevelopment,
      plugins: <AuthServerPlugin<EngineContext>>[organizations],
      passwordHasher: _demoPasswordHasher(),
      enforceCsrf: false,
    ),
    sessionAuth: sessionAuth,
  );

  // Haigate and the guard registry are process-level facades. The example may
  // be rebuilt by a test or a hot-reload cycle, so replace these example-only
  // registrations before binding the callbacks to this engine's store.
  guardRegistry.unregister('authenticated');
  Haigate.unregister('projects.create');
  guardRegistry.register(
    'authenticated',
    requireAuthenticated(sessionAuth: sessionAuth, realm: 'Tenant example'),
  );
  Haigate.register('projects.create', (evaluation) async {
    final organizationId = _organizationId(evaluation.context);
    if (organizationId == null) return false;
    return Haigate.canInOrganization(
      ctx: evaluation.context,
      plugin: organizations,
      organizationId: organizationId,
      resource: 'projects',
      action: 'create',
    );
  });

  final engine = Engine(
    providers: <ServiceProvider>[
      ...Engine.defaultProviders,
      RoutedSessionsProvider(
        SessionConfig.cookie(
          appKey: _appKey,
          cookieName: 'tenant_example_session',
          options: SessionOptions(secure: false, httpOnly: true),
        ),
      ),
      RoutedDatabaseProvider(
        manager: databases,
        migrations: <MigrationEntry>[
          ...authSchema.migrations,
          ...organizationSchema.migrations,
          ...appMigrations,
        ],
        migrateOnBoot: true,
      ),
    ],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(sessionAuth.middleware());
  AuthRoutes(authManager).register(engine.defaultRouter);

  engine.get('/', (ctx) {
    return ctx.json({
      'service': 'routed_tenant_architecture',
      'fixtures': {
        'alice': 'alice@example.com / password123 (Acme owner)',
        'bob': 'bob@example.com / password123 (Acme member, Beta owner)',
      },
      'tenantHeader': 'X-Organization-Id',
    });
  });

  engine.get(
    '/api/me',
    (ctx) {
      final principal = SessionAuth.current(ctx)!;
      return ctx.json(principal);
    },
    middlewares: <Middleware>[
      guardMiddleware(['authenticated']),
    ],
  );

  engine.get(
    '/api/projects',
    (ctx) async {
      final tenant = await _tenantOrRespond(ctx, organizations);
      if (tenant == null) return ctx.response;
      final rows = await _projects(
        ctx.db(),
      ).whereEquals('tenant_id', tenant.organization.id).orderBy('id').get();
      return ctx.json({'tenant': tenant.organization.slug, 'data': rows});
    },
    middlewares: <Middleware>[
      guardMiddleware(['authenticated']),
    ],
  );

  engine.post(
    '/api/projects',
    (ctx) async {
      final tenant = await _tenantOrRespond(ctx, organizations);
      if (tenant == null) return ctx.response;
      final payload = Map<String, dynamic>.from(
        await ctx.bindJSON({}) as Map? ?? const {},
      );
      final name = payload['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        return ctx.json({'error': 'name_required'}, statusCode: 422);
      }
      final principal = SessionAuth.current(ctx)!;
      await _projects(ctx.db()).insertManyInputs([
        {
          'tenant_id': tenant.organization.id,
          'owner_id': principal.id,
          'name': name,
        },
      ], returning: false);
      return ctx.json({
        'created': true,
        'tenant': tenant.organization.slug,
        'name': name,
      }, statusCode: HttpStatus.created);
    },
    middlewares: <Middleware>[
      guardMiddleware(['authenticated']),
      Haigate.middleware(['projects.create']),
    ],
  );

  engine.delete(
    '/api/projects/{id}',
    (ctx) async {
      final tenant = await _tenantOrRespond(ctx, organizations);
      if (tenant == null) return ctx.response;
      final id = int.tryParse(ctx.mustGetParam<String>('id'));
      if (id == null) {
        return ctx.json({'error': 'invalid_id'}, statusCode: 400);
      }
      final rows = await _projects(ctx.db())
          .whereEquals('id', id)
          .whereEquals('tenant_id', tenant.organization.id)
          .select(['id', 'owner_id'])
          .get();
      if (rows.isEmpty) {
        return ctx.json({'error': 'not_found'}, statusCode: 404);
      }
      final allowed = await Haigate.ownsOrCanInOrganization(
        ctx: ctx,
        plugin: organizations,
        organizationId: tenant.organization.id,
        resourceOwnerId: rows.first['owner_id']?.toString() ?? '',
        resource: 'projects',
        action: 'delete',
      );
      if (!allowed) {
        return ctx.json({'error': 'forbidden'}, statusCode: 403);
      }
      await _projects(ctx.db())
          .whereEquals('id', id)
          .whereEquals('tenant_id', tenant.organization.id)
          .delete();
      return ctx.json({'deleted': true, 'id': id});
    },
    middlewares: <Middleware>[
      guardMiddleware(['authenticated']),
    ],
  );

  await engine.initialize();
  // RoutedDatabaseProvider opens the manager and applies both the auth and
  // application migration ledgers before durable fixtures are read or seeded.
  await _seedAuth(authStore, organizationStore);
  await _seedProjects(engine.container.get<DatabaseManager>().database());
  return engine;
}

String? _organizationId(EngineContext ctx) {
  final header = ctx.request.headers.value('x-organization-id')?.trim();
  if (header != null && header.isNotEmpty) return header;
  final query = ctx.query('organizationId')?.toString().trim();
  return query == null || query.isEmpty ? null : query;
}

Future<AuthOrganizationAuthorizationContext<EngineContext>?> _tenantOrRespond(
  EngineContext ctx,
  OrganizationPlugin<EngineContext> organizations,
) async {
  final organizationId = _organizationId(ctx);
  if (organizationId == null) {
    ctx.json({'error': 'organization_required'}, statusCode: 400);
    return null;
  }
  try {
    return await Haigate.organizationContext(
      ctx: ctx,
      plugin: organizations,
      organizationId: organizationId,
    );
  } on AuthFlowException catch (error) {
    final status = error.code == 'unauthorized' ? 401 : 403;
    ctx.json({'error': error.code}, statusCode: status);
    return null;
  }
}

Future<void> _seedAuth(
  AuthStore store,
  AuthOrganizationStore organizations,
) async {
  final hasher = _demoPasswordHasher();
  final now = DateTime.now().toUtc();
  for (final user in <AuthUser>[
    AuthUser(id: aliceId, email: 'alice@example.com', name: 'Alice'),
    AuthUser(id: bobId, email: 'bob@example.com', name: 'Bob'),
  ]) {
    final existing = await store.users.findById(user.id);
    if (existing == null) {
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
  await _ensureTenant(
    organizations,
    id: acmeId,
    name: 'Acme',
    slug: 'acme',
    ownerId: aliceId,
  );
  if (await organizations.findMember(acmeId, bobId) == null) {
    await organizations.addMember(
      AuthOrganizationMember(
        id: 'membership-acme-bob',
        organizationId: acmeId,
        userId: bobId,
        roles: const <String>['member'],
        createdAt: now,
      ),
    );
  }
  await _ensureTenant(
    organizations,
    id: betaId,
    name: 'Beta',
    slug: 'beta',
    ownerId: bobId,
  );
}

Future<void> _ensureTenant(
  AuthOrganizationStore store, {
  required String id,
  required String name,
  required String slug,
  required String ownerId,
}) async {
  final existing = await store.findOrganization(id);
  if (existing != null) {
    if (await store.findMember(id, ownerId) == null) {
      await store.addMember(
        AuthOrganizationMember(
          id: 'membership-$slug-owner',
          organizationId: id,
          userId: ownerId,
          roles: const <String>['owner'],
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    return;
  }
  final now = DateTime.now().toUtc();
  await store.createOrganization(
    AuthOrganizationCreateTransaction(
      organization: AuthOrganization(
        id: id,
        name: name,
        slug: slug,
        createdAt: now,
        updatedAt: now,
      ),
      creatorMembership: AuthOrganizationMember(
        id: 'membership-$slug-owner',
        organizationId: id,
        userId: ownerId,
        roles: const <String>['owner'],
        createdAt: now,
      ),
      organizationLimit: null,
    ),
  );
}

Future<void> _seedProjects(OrmDatabase database) async {
  final existing = await _projects(database).get();
  if (existing.isNotEmpty) return;
  await _projects(database).insertManyInputs([
    {'tenant_id': acmeId, 'owner_id': aliceId, 'name': 'Acme private project'},
    {'tenant_id': betaId, 'owner_id': bobId, 'name': 'Beta private project'},
  ], returning: false);
}

Query<AdHocRow> _projects(OrmDatabase database) =>
    database.table('projects', columns: _projectColumns);
