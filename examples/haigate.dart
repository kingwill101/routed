import 'dart:convert';

import 'package:routed/routed.dart';

const _appKey =
    'base64:MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Ng==';

final users = <String, Map<String, Object?>>{
  'editor': {
    'password': 'password123',
    'roles': ['publisher'],
    'name': 'Casey',
  },
  'viewer': {
    'password': 'password123',
    'roles': ['viewer'],
    'name': 'Morgan',
  },
};

Future<void> main() async {
  SessionAuth.configure(rememberStore: InMemoryRememberTokenStore());

  GuardRegistry.instance.register(
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
    options: [
      withSessionConfig(
        SessionConfig.cookie(appKey: _appKey, cookieName: 'haigate_session'),
      ),
    ],
  );

  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

  engine.post('/login', (ctx) async {
    final body = jsonDecode(await ctx.body()) as Map<String, Object?>;

    final username = body['username']?.toString() ?? '';
    final password = body['password']?.toString() ?? '';

    final record = users[username];
    if (record == null || record['password'] != password) {
      ctx.status(HttpStatus.unauthorized);
      ctx.write('Invalid credentials');
      return ctx.string('');
    }

    final principal = AuthPrincipal(
      id: username,
      roles: List<String>.from(record['roles'] as List),
      attributes: {'name': record['name']},
    );

    await SessionAuth.login(ctx, principal, rememberMe: true);
    return ctx.json({'status': 'ok', 'roles': principal.roles});
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

  await engine.initialize();
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
