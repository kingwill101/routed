import 'dart:convert';
import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';

const _appKey =
    'base64:MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Ng==';

Future<void> main() async {
  final databasePath =
      Platform.environment['AUTH_DATABASE_PATH'] ?? 'storage/haigate.sqlite';
  File(databasePath).absolute.parent.createSync(recursive: true);
  final database = await SqliteDatabase.connect(path: databasePath);
  final schema = const OrmAuthSchema(tablePrefix: 'haigate');
  final store = OrmAuthStore(database, schema: schema);
  final databases = DatabaseManager()..register('default', database);
  SessionAuth.configure(
    rememberStore: OrmRememberTokenStore(database, schema: schema),
  );

  guardRegistry.register(
    'authenticated',
    requireAuthenticated(realm: 'Haigate Example'),
  );

  Haigate.register('reports.publish', (evaluation) {
    final principal = evaluation.principal;
    if (principal == null) return false;
    return principal.hasRole('publisher');
  });

  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [
      RoutedDatabaseProvider(
        manager: databases,
        migrations: schema.migrations,
        migrateOnBoot: true,
      ),
      ...Engine.defaultProviders,
      RoutedSessionsProvider(
        SessionConfig.cookie(appKey: _appKey, cookieName: 'haigate_session'),
      ),
    ],
  );

  final authOptions = AuthOptions<EngineContext>(
    providers: [CredentialsProvider()],
    store: store,
    storeMode: AuthStoreMode.durable,
    runtimeMode: AuthRuntimeMode.localDevelopment,
  );
  engine.container.instance<AuthOptions>(authOptions);

  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

  await engine.initialize();
  await _seedUsers(store);
  final authManager = AuthManager(
    authOptions,
    sessionAuth: SessionAuth.instance,
  );
  engine.container.instance<AuthManager>(authManager);

  engine.post('/login', (ctx) async {
    final body = jsonDecode(await ctx.body()) as Map<String, Object?>;

    final username = body['username']?.toString() ?? '';
    final password = body['password']?.toString() ?? '';

    final user = await store.users.findById(username);
    if (user == null) {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('Invalid credentials');
      return ctx.string('');
    }
    try {
      final provider = authManager.runtime.providers
          .whereType<CredentialsProvider>()
          .first;
      final result = await authManager.signInWithCredentials(
        ctx,
        provider,
        AuthCredentials(email: user.email!, password: password),
      );
      await SessionAuth.login(ctx, result.user.toPrincipal(), rememberMe: true);
      return ctx.json({'status': 'ok', 'roles': result.session.user.roles});
    } on AuthFlowException {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('Invalid credentials');
      return ctx.string('');
    }
  });

  engine.get(
    '/me',
    (ctx) => ctx.json(SessionAuth.current(ctx)),
    middlewares: [
      guardMiddleware(['authenticated']),
    ],
  );

  engine.post(
    '/reports/publish',
    (ctx) async {
      await Haigate.authorize('reports.publish', ctx: ctx);
      return ctx.json({'status': 'published'});
    },
    middlewares: [
      guardMiddleware(['authenticated']),
      Haigate.middleware(['reports.publish']),
    ],
  );

  engine.post('/logout', (ctx) async {
    await SessionAuth.logout(ctx);
    ctx.destroySession();
    return ctx.json({'status': 'signed-out'});
  });

  print('Haigate example listening on http://localhost:8080');
  print('1) Login as publisher:');
  print(
    '   curl -i -c cookies.txt -H "Content-Type: application/json" '
    '-d \'{"username":"editor","password":"password123"}\' http://localhost:8080/login',
  );
  print('2) Publish a report:');
  print(
    '   curl -i -b cookies.txt -X POST http://localhost:8080/reports/publish',
  );
  print('3) Logout:');
  print('   curl -i -b cookies.txt -X POST http://localhost:8080/logout');

  await engine.serve(host: 'localhost', port: 8080);
}

Future<void> _seedUsers(OrmAuthStore store) async {
  final hasher = Argon2idPasswordHasher(
    iterations: 1,
    memoryKiB: 8,
    derivedKeyLength: 16,
  );
  final now = DateTime.now().toUtc();
  for (final user in <AuthUser>[
    AuthUser(
      id: 'editor',
      name: 'Casey',
      email: 'editor@haigate.example',
      roles: ['publisher'],
    ),
    AuthUser(
      id: 'viewer',
      name: 'Morgan',
      email: 'viewer@haigate.example',
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
