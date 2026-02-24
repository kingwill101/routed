import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthConfig.fromMap parses normalized auth config payload', () {
    final config = AuthConfig.fromMap({
      'jwt': {
        'enabled': true,
        'issuer': ' https://issuer.example ',
        'audience': ['app'],
        'required_claims': ['sub'],
        'algorithms': ['RS256'],
        'keys': [
          {'kty': 'RSA', 'kid': 'one'},
        ],
      },
      'oauth2': {
        'introspection': {
          'enabled': true,
          'endpoint': 'https://oauth.example/introspect',
          'additional': {'resource': 'api'},
        },
      },
      'session': {
        'strategy': 'jwt',
        'remember_me': {'cookie': 'remember', 'duration': '14d'},
      },
      'features': {
        'haigate': {'enabled': true},
      },
      'gates': {
        'defaults': {'denied_status': 418},
        'abilities': {
          'posts.manage': {
            'type': 'roles',
            'roles': ['admin'],
            'any': true,
          },
        },
      },
      'guards': {
        'auth': {'type': 'authenticated', 'realm': 'Members'},
      },
    });

    expect(config.jwt.enabled, isTrue);
    expect(config.jwt.issuer, 'https://issuer.example');
    expect(config.oauth2Introspection.endpoint, isNotNull);
    expect(config.session.strategy, AuthSessionStrategy.jwt);
    expect(config.sessionRememberMe.cookieName, 'remember');
    expect(config.haigate.enabled, isTrue);
    expect(config.haigate.defaults.statusCode, 418);
    expect(config.haigate.abilities['posts.manage']?.type, GateType.roles);
    expect(config.guards['auth']?.type, GuardType.authenticated);
  });

  test('GateDefinition parsing supports string and map shorthand', () {
    final auth = GateDefinition.fromSpec('authenticated', context: 'g.auth');
    final roles = GateDefinition.fromSpec({
      'type': 'roles_any',
      'roles': ['admin', 'editor'],
    }, context: 'g.roles');

    expect(auth?.type, GateType.authenticated);
    expect(roles?.type, GateType.roles);
    expect(roles?.any, isTrue);
    expect(roles?.roles, ['admin', 'editor']);
  });

  test(
    'resolveConfiguredGateCallback materializes callback from definition',
    () async {
      final callback = resolveConfiguredGateCallback<String>(
        const GateDefinition.roles(roles: ['admin']),
      );

      final allowed = await callback!(
        AuthGateEvaluationContext<String>(
          context: 'ctx',
          principal: AuthPrincipal(id: '1', roles: const ['admin']),
        ),
      );

      expect(allowed, isTrue);
    },
  );

  test('resolveConfiguredGuard chooses factories by definition type', () async {
    final authGuard = resolveConfiguredGuard<String, String>(
      definition: const GuardDefinition.authenticated(realm: 'Members'),
      authenticatedGuard: (realm) =>
          (_) => GuardResult<String>.deny('auth:$realm'),
      rolesGuard: (roles, any) =>
          (_) => GuardResult<String>.allow(),
    );
    final rolesGuard = resolveConfiguredGuard<String, String>(
      definition: const GuardDefinition.roles(roles: ['admin'], any: true),
      authenticatedGuard: (_) =>
          (_) => GuardResult<String>.allow(),
      rolesGuard: (roles, any) =>
          (_) => GuardResult<String>.deny('roles:${roles.join(',')}:$any'),
    );

    final authResult = await authGuard!('ctx');
    final rolesResult = await rolesGuard!('ctx');

    expect(authResult.allowed, isFalse);
    expect(authResult.response, 'auth:Members');
    expect(rolesResult.allowed, isFalse);
    expect(rolesResult.response, 'roles:admin:true');
  });

  test(
    'resolveConfiguredGuard returns null for empty roles guard definitions',
    () {
      final guard = resolveConfiguredGuard<String, String>(
        definition: const GuardDefinition.roles(roles: []),
        authenticatedGuard: (_) =>
            (_) => GuardResult<String>.allow(),
        rolesGuard: (roles, any) =>
            (_) => GuardResult<String>.allow(),
      );

      expect(guard, isNull);
    },
  );
}
