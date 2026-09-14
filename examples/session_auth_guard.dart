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
      Platform.environment['AUTH_DATABASE_PATH'] ??
      'storage/session_auth_guard.sqlite';
  File(databasePath).absolute.parent.createSync(recursive: true);
  final database = await SqliteDatabase.connect(path: databasePath);
  final schema = const OrmAuthSchema(tablePrefix: 'session_auth_guard');
  final store = OrmAuthStore(database, schema: schema);
  final databases = DatabaseManager()..register('default', database);
  SessionAuth.configure(
    rememberStore: OrmRememberTokenStore(database, schema: schema),
  );

  guardRegistry
    ..register('authenticated', requireAuthenticated(realm: 'Example App'))
    ..register('admin-only', requireRoles(['admin']));

  Haigate.register('reports.publish', (evaluation) {
    final principal = evaluation.principal;
    if (principal == null) return false;
    return principal.hasRole('admin') || principal.hasRole('support');
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
        SessionConfig.cookie(appKey: _appKey, cookieName: 'example_session'),
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

  engine.get('/', (ctx) {
    return ctx.json({
      'message': 'Session auth example',
      'routes': {
        'POST /login':
            'Sign in with username, password, and optional remember flag',
        'GET /whoami': 'Returns the current principal (requires authenticated)',
        'GET /admin': 'Admin-only route enforced by guard middleware',
        'POST /logout': 'Clears session and remember token',
      },
    });
  });

  await engine.initialize();
  await _seedUsers(store);
  final authManager = AuthManager(
    authOptions,
    sessionAuth: SessionAuth.instance,
  );
  engine.container.instance<AuthManager>(authManager);

  engine.post('/login', (ctx) async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await ctx.body()) as Map<String, dynamic>;
    } catch (_) {
      ctx.status(HttpStatus.badRequest);
      ctx.write('Invalid JSON payload');
      return ctx.string('');
    }

    final username = payload['username']?.toString() ?? '';
    final password = payload['password']?.toString() ?? '';
    final remember = payload['remember'] == true;

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
      if (remember) {
        await SessionAuth.login(
          ctx,
          result.user.toPrincipal(),
          rememberMe: true,
        );
      }
      return ctx.json({
        'id': result.session.user.id,
        'roles': result.session.user.roles,
        'remember': remember,
      });
    } on AuthFlowException {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('Invalid credentials');
      return ctx.string('');
    }
  });

  engine.get(
    '/whoami',
    (ctx) {
      final principal = SessionAuth.current(ctx)!;
      return ctx.json({
        'id': principal.id,
        'roles': principal.roles,
        'attributes': principal.attributes,
      });
    },
    middlewares: [
      guardMiddleware(['authenticated']),
    ],
  );

  engine.get(
    '/admin',
    (ctx) {
      final principal = SessionAuth.current(ctx)!;
      return ctx.json({
        'message': 'Welcome, ${principal.attributes['name']}!',
        'roles': principal.roles,
      });
    },
    middlewares: [
      guardMiddleware(['authenticated', 'admin-only']),
    ],
  );

  engine.post(
    '/reports/publish',
    (ctx) => ctx.json({'status': 'published'}),
    middlewares: [
      Haigate.middleware(['reports.publish']),
    ],
  );

  engine.post('/logout', (ctx) async {
    await SessionAuth.logout(ctx);
    ctx.destroySession();
    return ctx.json({'message': 'Signed out'});
  });

  print('Session auth guard example listening on http://localhost:8080');
  print('1) Sign in as admin and store cookies:');
  print('''   curl -i -c cookies.txt -H "Content-Type: application/json" \\''');
  print(
    '        -d \'{"username":"taylor","password":"password123","remember":true}\' http://localhost:8080/login',
  );
  print('2) Call an authenticated route:');
  print('   curl -i -b cookies.txt http://localhost:8080/whoami');
  print('3) Hit the admin-only guard:');
  print('   curl -i -b cookies.txt http://localhost:8080/admin');
  print('4) Sign out and clear tokens:');
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
      id: 'taylor',
      name: 'Taylor',
      email: 'taylor@session.example',
      roles: ['admin'],
    ),
    AuthUser(
      id: 'sasha',
      name: 'Sasha',
      email: 'sasha@session.example',
      roles: ['support'],
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
