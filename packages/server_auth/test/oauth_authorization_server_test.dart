import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'authorization endpoint issues a bound code and token exchange is one-time',
    () async {
      final store = InMemoryAuthStore();
      await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final feature = OAuthAuthorizationServerPlugin<String>(
        authorizationCodes: InMemoryAuthOAuthAuthorizationCodeStore(),
        resolveClient: (_, clientId) async => clientId == 'client-1'
            ? AuthOAuthAuthorizationClient(
                clientId: clientId,
                redirectUris: [Uri.parse('https://client.example/callback')],
                scopes: ['mcp:read'],
              )
            : null,
        issueAccessToken: (_, record) => AuthDeviceAccessToken(
          accessToken: 'access-${record.userId}',
          expiresIn: const Duration(minutes: 5),
          scopes: record.scopes,
        ),
      )..configure(AuthServerPluginContext<String>(store: store));
      final authorize = feature.endpoints.singleWhere(
        (endpoint) => endpoint.id == 'oauthAuthorizationServer.authorize',
      );
      final authorization = await authorize.invoke(
        AuthOperationInvocation<String>(
          context: 'context',
          user: AuthUser(id: 'user-1', email: 'user@example.com'),
        ),
        const <String, dynamic>{
          'client_id': 'client-1',
          'redirect_uri': 'https://client.example/callback',
          'response_type': 'code',
          'scope': 'mcp:read',
          'state': 'state-1',
          'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          'code_challenge_method': 'S256',
        },
      );
      final redirect = authorization! as AuthEndpointRedirect;
      expect(redirect.statusCode, 302);
      expect(redirect.location.fragment, isEmpty);
      expect(redirect.location.queryParameters['state'], 'state-1');
      final code = redirect.location.queryParameters['code'];
      expect(code, isNotNull);

      final token = feature.endpoints.singleWhere(
        (endpoint) => endpoint.id == 'oauthAuthorizationServer.token',
      );
      final tokenResponse = await token.invoke(
        const AuthOperationInvocation<String>(context: 'context', user: null),
        <String, dynamic>{
          'grant_type': 'authorization_code',
          'client_id': 'client-1',
          'redirect_uri': 'https://client.example/callback',
          'code': code,
          'code_verifier': 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        },
      );
      expect((tokenResponse! as Map)['access_token'], 'access-user-1');
      await expectLater(
        token.invoke(
          const AuthOperationInvocation<String>(context: 'context', user: null),
          <String, dynamic>{
            'grant_type': 'authorization_code',
            'client_id': 'client-1',
            'redirect_uri': 'https://client.example/callback',
            'code': code,
            'code_verifier': 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
          },
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_grant',
          ),
        ),
      );
    },
  );

  test('authorization endpoint never redirects an unregistered URI', () async {
    final feature = OAuthAuthorizationServerPlugin<Object>(
      authorizationCodes: InMemoryAuthOAuthAuthorizationCodeStore(),
      resolveClient: (_, _) => AuthOAuthAuthorizationClient(
        clientId: 'client-1',
        redirectUris: [Uri.parse('https://client.example')],
      ),
      issueAccessToken: (_, _) => const AuthDeviceAccessToken(
        accessToken: 'unused',
        expiresIn: Duration(minutes: 1),
      ),
    );
    final endpoint = feature.endpoints.first;
    await expectLater(
      endpoint.invoke(
        AuthOperationInvocation<Object>(
          context: Object(),
          user: AuthUser(id: 'user-1'),
        ),
        const <String, dynamic>{
          'client_id': 'client-1',
          'redirect_uri': 'https://evil.example/callback',
          'response_type': 'code',
          'code_challenge': 'challenge',
          'code_challenge_method': 'S256',
        },
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'invalid_redirect_uri',
        ),
      ),
    );
  });

  test('token exchange rejects a user disabled after authorization', () async {
    final store = InMemoryAuthStore();
    await store.users.create(AuthUser(id: 'user-1'));
    var issued = false;
    final feature = OAuthAuthorizationServerPlugin<Object>(
      authorizationCodes: InMemoryAuthOAuthAuthorizationCodeStore(),
      resolveClient: (_, _) => AuthOAuthAuthorizationClient(
        clientId: 'client-1',
        redirectUris: [Uri.parse('https://client.example/callback')],
      ),
      issueAccessToken: (_, _) {
        issued = true;
        return const AuthDeviceAccessToken(
          accessToken: 'must-not-be-issued',
          expiresIn: Duration(minutes: 1),
        );
      },
    )..configure(AuthServerPluginContext<Object>(store: store));
    final authorize = feature.endpoints.first;
    final redirect =
        await authorize.invoke(
              AuthOperationInvocation<Object>(
                context: Object(),
                user: AuthUser(id: 'user-1'),
              ),
              const <String, dynamic>{
                'client_id': 'client-1',
                'redirect_uri': 'https://client.example/callback',
                'response_type': 'code',
                'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
                'code_challenge_method': 'S256',
              },
            )
            as AuthEndpointRedirect;
    await store.disable('user-1', reason: 'security');

    await expectLater(
      feature.endpoints.last.invoke(
        AuthOperationInvocation<Object>(context: Object(), user: null),
        <String, dynamic>{
          'grant_type': 'authorization_code',
          'client_id': 'client-1',
          'redirect_uri': 'https://client.example/callback',
          'code': redirect.location.queryParameters['code'],
          'code_verifier': 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        },
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'invalid_grant',
        ),
      ),
    );
    expect(issued, isFalse);
  });
}
