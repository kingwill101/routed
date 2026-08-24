import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthConfig.defaults provides typed safe defaults', () {
    final config = AuthConfig.defaults();

    expect(config.jwt.enabled, isFalse);
    expect(config.jwt.requiredClaims, <String>['exp']);
    expect(config.oauth2Introspection.enabled, isFalse);
    expect(config.session.rememberMe.cookieName, 'remember_token');
    expect(config.haigate.enabled, isFalse);
    expect(config.guards, isEmpty);
  });

  test('AuthConfig stores typed sections without map materialization', () {
    final config = AuthConfig.defaults().copyWith(
      jwt: const AuthJwtConfig(
        enabled: true,
        issuer: 'https://issuer.example',
        audience: ['app'],
        requiredClaims: ['sub'],
        jwksUri: null,
        jwksCacheTtl: Duration(minutes: 5),
        clockSkew: Duration(seconds: 60),
        algorithms: ['RS256'],
        inlineKeys: [
          {'kty': 'RSA', 'kid': 'one'},
        ],
        header: 'Authorization',
        bearerPrefix: 'Bearer ',
      ),
      oauth2Introspection: OAuthIntrospectionConfig(
        enabled: true,
        endpoint: Uri.parse('https://oauth.example/introspect'),
        clientId: null,
        clientSecret: null,
        tokenTypeHint: null,
        cacheTtl: Duration.zero,
        clockSkew: const Duration(seconds: 60),
        additionalParameters: {'resource': 'api'},
      ),
      session: const AuthSessionConfig(
        strategy: AuthSessionStrategy.jwt,
        maxAge: null,
        updateAge: null,
        rememberMe: SessionRememberMeConfig(
          cookieName: 'remember',
          duration: Duration(days: 14),
        ),
      ),
      haigate: const HaigateConfig(
        enabled: true,
        defaults: GateDefaults(statusCode: 418),
        abilities: {
          'posts.manage': GateDefinition.roles(roles: ['admin'], any: true),
        },
      ),
      guards: const {'auth': GuardDefinition.authenticated(realm: 'Members')},
    );

    expect(config.jwt.enabled, isTrue);
    expect(config.jwt.issuer, 'https://issuer.example');
    expect(config.oauth2Introspection.endpoint, isNotNull);
    expect(config.session.strategy, AuthSessionStrategy.jwt);
    expect(config.session.rememberMe.cookieName, 'remember');
    expect(config.haigate.enabled, isTrue);
    expect(config.haigate.defaults.statusCode, 418);
    expect(config.haigate.abilities['posts.manage']?.type, GateType.roles);
    expect(config.guards['auth']?.type, GuardType.authenticated);
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
          (_) => const GuardResult<String>.allow(),
    );
    final rolesGuard = resolveConfiguredGuard<String, String>(
      definition: const GuardDefinition.roles(roles: ['admin'], any: true),
      authenticatedGuard: (_) =>
          (_) => const GuardResult<String>.allow(),
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
            (_) => const GuardResult<String>.allow(),
        rolesGuard: (roles, any) =>
            (_) => const GuardResult<String>.allow(),
      );

      expect(guard, isNull);
    },
  );
}
