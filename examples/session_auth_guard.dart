import 'dart:convert';

import 'package:routed/routed.dart';

const _appKey =
    'base64:MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Ng==';

final Map<String, Map<String, dynamic>> _users = <String, Map<String, dynamic>>{
  'taylor': {
    'password': 'password123',
    'roles': ['admin'],
    'name': 'Taylor',
  },
  'sasha': {
    'password': 'password123',
    'roles': ['support'],
    'name': 'Sasha',
  },
};

Future<void> main() async {
  SessionAuth.configure(rememberStore: InMemoryRememberTokenStore());

  GuardRegistry.instance
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
    options: [
      withSessionConfig(
        SessionConfig.cookie(appKey: _appKey, cookieName: 'example_session'),
      ),
    ],
  );

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

    final record = _users[username];
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

    await SessionAuth.login(ctx, principal, rememberMe: remember);

    return ctx.json({
      'id': principal.id,
      'roles': principal.roles,
      'remember': remember,
    });
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

  await engine.initialize();

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
