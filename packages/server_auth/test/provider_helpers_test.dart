import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('resolveAuthProviderById finds provider by exact id', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    expect(resolveAuthProviderById(providers, 'google')?.name, 'Google');
    expect(resolveAuthProviderById(providers, 'missing'), isNull);
    expect(resolveAuthProviderById(providers, '   '), isNull);
  });

  test('authProviderSummaries returns stable provider payloads', () {
    final providers = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];

    expect(
      authProviderSummaries(providers),
      equals(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'google', 'name': 'Google', 'type': 'oidc'},
      ]),
    );
  });

  test('mergeAuthProvidersById appends only missing providers', () {
    final base = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
    ];
    final additional = <AuthProvider>[
      AuthProvider(id: 'google', name: 'Google 2', type: AuthProviderType.oidc),
      AuthProvider(id: 'github', name: 'GitHub', type: AuthProviderType.oauth),
    ];

    final merged = mergeAuthProvidersById(base, additional);

    expect(
      merged.map((provider) => provider.id),
      equals(<String>['google', 'github']),
    );
    expect(merged.first.name, equals('Google'));
  });

  test(
    'resolveOAuthUserForAccount updates linked users when profile changes',
    () async {
      var updated = false;
      final adapter = CallbackAuthAdapter(
        onGetAccount: (providerId, providerAccountId) {
          return AuthAccount(
            providerId: providerId,
            providerAccountId: providerAccountId,
            userId: 'user-1',
          );
        },
        onGetUserById: (id) async {
          expect(id, equals('user-1'));
          return AuthUser(
            id: 'user-1',
            email: 'old@example.com',
            name: 'Old Name',
            attributes: const <String, dynamic>{'legacy': true},
          );
        },
        onGetUserByEmail: (_) => null,
        onUpdateUser: (user) async {
          updated = true;
          return user;
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        adapter: adapter,
        providerId: 'github',
        accountId: 'acct-1',
        mappedUser: AuthUser(
          id: 'provider-user',
          email: 'new@example.com',
          name: 'New Name',
          attributes: const <String, dynamic>{'fresh': true},
        ),
      );

      expect(resolved.isNewUser, isFalse);
      expect(resolved.userUpdated, isTrue);
      expect(resolved.user.id, equals('user-1'));
      expect(resolved.user.email, equals('new@example.com'));
      expect(resolved.user.attributes['legacy'], isTrue);
      expect(resolved.user.attributes['fresh'], isTrue);
      expect(updated, isTrue);
    },
  );

  test(
    'resolveOAuthUserForAccount creates user when no records resolve',
    () async {
      var created = false;
      final adapter = CallbackAuthAdapter(
        onGetAccount: (_, _) => null,
        onGetUserByEmail: (_) => null,
        onCreateUser: (user) async {
          created = true;
          return AuthUser(
            id: 'created-user',
            email: user.email,
            name: user.name,
            attributes: user.attributes,
          );
        },
      );

      final resolved = await resolveOAuthUserForAccount(
        adapter: adapter,
        providerId: 'google',
        accountId: 'acct-2',
        mappedUser: AuthUser(
          id: '',
          email: 'new@example.com',
          name: 'New User',
        ),
      );

      expect(resolved.isNewUser, isTrue);
      expect(resolved.userUpdated, isFalse);
      expect(resolved.user.id, equals('created-user'));
      expect(created, isTrue);
    },
  );

  test('exchangeOAuthAuthorizationCode uses provider token settings', () async {
    late http.Request captured;
    final provider = OAuthProvider<Map<String, dynamic>>(
      id: 'example',
      name: 'Example',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
      tokenEndpoint: Uri.parse('https://auth.test/token'),
      redirectUri: 'https://app.test/callback/example',
      scopes: const <String>['openid', 'profile'],
      tokenParams: const <String, String>{'resource': 'api'},
      profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
    );

    final token = await exchangeOAuthAuthorizationCode(
      provider,
      code: 'auth-code',
      codeVerifier: 'pkce-verifier',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': 'token-1',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(token.accessToken, equals('token-1'));
    expect(captured.bodyFields['grant_type'], equals('authorization_code'));
    expect(captured.bodyFields['code'], equals('auth-code'));
    expect(
      captured.bodyFields['redirect_uri'],
      equals('https://app.test/callback/example'),
    );
    expect(captured.bodyFields['scope'], equals('openid profile'));
    expect(captured.bodyFields['code_verifier'], equals('pkce-verifier'));
    expect(captured.bodyFields['resource'], equals('api'));
  });

  test(
    'buildOAuthAuthorizationParameters includes scopes, pkce and callback',
    () {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'example',
        name: 'Example',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/example',
        scopes: const <String>['openid', 'profile'],
        authorizationParams: const <String, String>{'prompt': 'consent'},
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      final params = buildOAuthAuthorizationParameters(
        provider,
        state: 'state-123',
        codeChallenge: 'challenge-xyz',
        callbackUrl: '/dashboard',
      );

      expect(params['response_type'], equals('code'));
      expect(params['client_id'], equals('client-id'));
      expect(
        params['redirect_uri'],
        equals('https://app.test/callback/example'),
      );
      expect(params['state'], equals('state-123'));
      expect(params['scope'], equals('openid profile'));
      expect(params['code_challenge'], equals('challenge-xyz'));
      expect(params['code_challenge_method'], equals('S256'));
      expect(params['callbackUrl'], equals('/dashboard'));
      expect(params['prompt'], equals('consent'));
    },
  );

  test(
    'loadOAuthProfile decodes id_token claims when no userinfo endpoint',
    () async {
      final header = base64UrlEncode(
        utf8.encode('{"alg":"none","typ":"JWT"}'),
      ).replaceAll('=', '');
      final payload = base64UrlEncode(
        utf8.encode('{"sub":"user-1","email":"user@example.com"}'),
      ).replaceAll('=', '');
      final idToken = '$header.$payload.';

      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'oidc',
        name: 'OIDC',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        redirectUri: 'https://app.test/callback/oidc',
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      final profile = await loadOAuthProfile(
        provider,
        token: OAuthTokenResponse(
          accessToken: 'access-token',
          tokenType: 'Bearer',
          expiresIn: 3600,
          raw: <String, dynamic>{'id_token': idToken},
        ),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(profile['sub'], equals('user-1'));
      expect(profile['email'], equals('user@example.com'));
    },
  );

  test(
    'loadOAuthProfile maps userinfo callback failures to AuthFlowException',
    () async {
      final provider = OAuthProvider<Map<String, dynamic>>(
        id: 'custom',
        name: 'Custom',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
        tokenEndpoint: Uri.parse('https://auth.test/token'),
        userInfoEndpoint: Uri.parse('https://auth.test/userinfo'),
        userInfoRequest: (token, client, endpoint) => throw StateError('boom'),
        redirectUri: 'https://app.test/callback/custom',
        profile: (profile) => AuthUser(id: profile['sub']?.toString() ?? ''),
      );

      await expectLater(
        loadOAuthProfile(
          provider,
          token: OAuthTokenResponse(
            accessToken: 'access-token',
            tokenType: 'Bearer',
            expiresIn: 3600,
            raw: const <String, dynamic>{},
          ),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'userinfo_failed',
          ),
        ),
      );
    },
  );
}
