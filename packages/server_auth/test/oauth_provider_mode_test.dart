import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _privateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgVPWE2CtYsptB+5el
350riIIY0ZtVdczOyzBbrzd35eGhRANCAARuazlUCWjnfWtrV2QlUk2I7fEVNbNI
v1Cf6Cuu9E0H1rQM6j9foo5KLK7on0e73Iy4jw15+O2CaRdmKONdKaOC
-----END PRIVATE KEY-----
''';

const _verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
const _challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

void main() {
  group('OAuthProviderModePlugin OIDC', () {
    late InMemoryAuthStore authStore;
    late InMemoryOAuthClientStore clientStore;
    late InMemoryOAuthAuthorizationCodeStore codeStore;
    late InMemoryOAuthAccessTokenStore tokenStore;
    late OAuthOidcConfiguration oidc;
    late OAuthProviderModePlugin<Object> plugin;

    setUp(() async {
      authStore = InMemoryAuthStore();
      await authStore.users.create(
        AuthUser(id: 'user-1', email: 'user@example.test', name: 'Routed User'),
      );
      clientStore = InMemoryOAuthClientStore();
      await clientStore.create(
        OAuthClient(
          clientId: 'client-1',
          clientSecretHash: sha256.convert(utf8.encode('secret')).toString(),
          name: 'OIDC client',
          redirectUris: const ['https://client.example.test/callback'],
          grantTypes: const ['authorization_code', 'refresh_token'],
          scopes: const ['openid', 'profile', 'email'],
        ),
      );
      codeStore = InMemoryOAuthAuthorizationCodeStore();
      tokenStore = InMemoryOAuthAccessTokenStore();
      oidc = OAuthOidcConfiguration(
        issuer: Uri.parse('https://issuer.example.test'),
        signingKey: JsonWebKey.fromPem(_privateKeyPem, keyId: 'oidc-key-1'),
        signingAlgorithm: 'ES256',
      );
      plugin = OAuthProviderModePlugin<Object>(
        clientStore: clientStore,
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
              authorizationCodeStore: codeStore,
              accessTokenStore: tokenStore,
            ),
        options: OAuthProviderModeOptions(oidc: oidc),
      )..configure(AuthServerPluginContext<Object>(store: authStore));
    });

    test('publishes truthful discovery metadata and a public JWKS', () async {
      final discoveryEndpoint = _endpoint(plugin, 'oauth_provider.discovery');
      expect(discoveryEndpoint.mount, AuthEndpointMount.root);
      final discoveryClient = plugin.clientOperations.singleWhere(
        (operation) => operation.id == 'oauth_provider.discovery',
      );
      expect(discoveryClient.mount, AuthEndpointMount.root);
      final discovery =
          await discoveryEndpoint.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(body: const <String, dynamic>{}),
              )
              as Map<String, dynamic>;
      expect(discovery['issuer'], 'https://issuer.example.test');
      expect(
        discovery['authorization_endpoint'],
        'https://issuer.example.test/oauth/authorize',
      );
      expect(discovery['jwks_uri'], 'https://issuer.example.test/oauth/jwks');
      expect(discovery, isNot(contains('registration_endpoint')));
      expect(
        discovery['id_token_signing_alg_values_supported'],
        equals(<String>['ES256']),
      );

      final jwks =
          await _endpoint(plugin, 'oauth_provider.jwks').invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(body: const <String, dynamic>{}),
              )
              as Map<String, dynamic>;
      final keys = jwks['keys'] as List<dynamic>;
      expect(keys, hasLength(1));
      final publicKey = keys.single as Map<String, dynamic>;
      expect(publicKey['kid'], 'oidc-key-1');
      expect(publicKey['alg'], 'ES256');
      expect(publicKey['use'], 'sig');
      expect(publicKey, containsPair('kty', 'EC'));
      expect(publicKey, contains('x'));
      expect(publicKey, contains('y'));
      expect(publicKey, isNot(contains('d')));
    });

    test('authorization code exchange issues a verifiable ID token', () async {
      final redirect =
          await _endpoint(plugin, 'oauth_provider.authorize').invoke(
                AuthOperationInvocation<Object>(
                  context: Object(),
                  user: AuthUser(id: 'user-1'),
                ),
                AuthEndpointRequest(
                  query: const <String, dynamic>{
                    'client_id': 'client-1',
                    'redirect_uri': 'https://client.example.test/callback',
                    'response_type': 'code',
                    'scope': 'openid profile email',
                    'nonce': 'nonce-1',
                    'code_challenge': _challenge,
                    'code_challenge_method': 'S256',
                  },
                ),
              )
              as AuthEndpointRedirect;

      final response =
          await _endpoint(plugin, 'oauth_provider.token').invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(
                  body: <String, dynamic>{
                    'grant_type': 'authorization_code',
                    'client_id': 'client-1',
                    'client_secret': 'secret',
                    'redirect_uri': 'https://client.example.test/callback',
                    'code': redirect.location.queryParameters['code'],
                    'code_verifier': _verifier,
                  },
                ),
              )
              as Map<String, dynamic>;

      expect(response['access_token'], isNotEmpty);
      expect(response['refresh_token'], isNotEmpty);
      final idToken = response['id_token'] as String;
      final verifier = JwtVerifier(
        options: JwtOptions(
          issuer: oidc.issuer.toString(),
          audience: const ['client-1'],
          requiredClaims: const ['exp', 'iat', 'sub'],
          inlineKeys: <Map<String, dynamic>>[oidc.publicJwk],
          algorithms: const ['ES256'],
        ),
      );
      final payload = await verifier.verifyToken(idToken);
      expect(payload.subject, 'user-1');
      expect(payload.claims['nonce'], 'nonce-1');
      expect(payload.claims['email'], 'user@example.test');
      expect(payload.claims['name'], 'Routed User');
    });

    test('OAuth-only grants do not receive an ID token', () async {
      final redirect =
          await _endpoint(plugin, 'oauth_provider.authorize').invoke(
                AuthOperationInvocation<Object>(
                  context: Object(),
                  user: AuthUser(id: 'user-1'),
                ),
                AuthEndpointRequest(
                  query: const <String, dynamic>{
                    'client_id': 'client-1',
                    'redirect_uri': 'https://client.example.test/callback',
                    'response_type': 'code',
                    'scope': 'profile',
                    'code_challenge': _challenge,
                    'code_challenge_method': 'S256',
                  },
                ),
              )
              as AuthEndpointRedirect;
      final response =
          await _endpoint(plugin, 'oauth_provider.token').invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(
                  body: <String, dynamic>{
                    'grant_type': 'authorization_code',
                    'client_id': 'client-1',
                    'client_secret': 'secret',
                    'redirect_uri': 'https://client.example.test/callback',
                    'code': redirect.location.queryParameters['code'],
                    'code_verifier': _verifier,
                  },
                ),
              )
              as Map<String, dynamic>;
      expect(response, isNot(contains('id_token')));
    });

    test('disabled users cannot exchange an issued code', () async {
      final redirect =
          await _endpoint(plugin, 'oauth_provider.authorize').invoke(
                AuthOperationInvocation<Object>(
                  context: Object(),
                  user: AuthUser(id: 'user-1'),
                ),
                AuthEndpointRequest(
                  query: const <String, dynamic>{
                    'client_id': 'client-1',
                    'redirect_uri': 'https://client.example.test/callback',
                    'response_type': 'code',
                    'scope': 'openid',
                    'code_challenge': _challenge,
                    'code_challenge_method': 'S256',
                  },
                ),
              )
              as AuthEndpointRedirect;
      await authStore.disable('user-1', reason: 'security');
      final request = <String, dynamic>{
        'grant_type': 'authorization_code',
        'client_id': 'client-1',
        'client_secret': 'secret',
        'redirect_uri': 'https://client.example.test/callback',
        'code': redirect.location.queryParameters['code'],
        'code_verifier': _verifier,
      };

      await expectLater(
        _endpoint(plugin, 'oauth_provider.token').invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          AuthEndpointRequest(body: request),
        ),
        _flow('invalid_grant'),
      );
      await authStore.enable('user-1');
      final response =
          await _endpoint(plugin, 'oauth_provider.token').invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(body: request),
              )
              as Map<String, dynamic>;
      expect(response['access_token'], isNotEmpty);
    });

    test('disabled clients do not burn an otherwise valid code', () async {
      final redirect =
          await _endpoint(plugin, 'oauth_provider.authorize').invoke(
                AuthOperationInvocation<Object>(
                  context: Object(),
                  user: AuthUser(id: 'user-1'),
                ),
                AuthEndpointRequest(
                  query: const <String, dynamic>{
                    'client_id': 'client-1',
                    'redirect_uri': 'https://client.example.test/callback',
                    'response_type': 'code',
                    'scope': 'profile',
                    'code_challenge': _challenge,
                    'code_challenge_method': 'S256',
                  },
                ),
              )
              as AuthEndpointRedirect;
      final client = (await clientStore.findById('client-1'))!;
      await clientStore.update(client.copyWith(enabled: false));
      final request = <String, dynamic>{
        'grant_type': 'authorization_code',
        'client_id': 'client-1',
        'client_secret': 'secret',
        'redirect_uri': 'https://client.example.test/callback',
        'code': redirect.location.queryParameters['code'],
        'code_verifier': _verifier,
      };

      await expectLater(
        _endpoint(plugin, 'oauth_provider.token').invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          AuthEndpointRequest(body: request),
        ),
        _flow('invalid_client'),
      );
      await clientStore.update(client.copyWith(enabled: true));
      final response =
          await _endpoint(plugin, 'oauth_provider.token').invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(body: request),
              )
              as Map<String, dynamic>;
      expect(response['access_token'], isNotEmpty);
    });

    test('locked accounts do not burn an otherwise valid code', () async {
      final redirect =
          await _endpoint(plugin, 'oauth_provider.authorize').invoke(
                AuthOperationInvocation<Object>(
                  context: Object(),
                  user: AuthUser(id: 'user-1'),
                ),
                AuthEndpointRequest(
                  query: const <String, dynamic>{
                    'client_id': 'client-1',
                    'redirect_uri': 'https://client.example.test/callback',
                    'response_type': 'code',
                    'scope': 'profile',
                    'code_challenge': _challenge,
                    'code_challenge_method': 'S256',
                  },
                ),
              )
              as AuthEndpointRedirect;
      await authStore.upsert(
        AuthAccountState(
          userId: 'user-1',
          lockedUntil: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        ),
      );
      final request = <String, dynamic>{
        'grant_type': 'authorization_code',
        'client_id': 'client-1',
        'client_secret': 'secret',
        'redirect_uri': 'https://client.example.test/callback',
        'code': redirect.location.queryParameters['code'],
        'code_verifier': _verifier,
      };

      await expectLater(
        _endpoint(plugin, 'oauth_provider.token').invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          AuthEndpointRequest(body: request),
        ),
        _flow('invalid_grant'),
      );
      await authStore.unlock('user-1');
      final response =
          await _endpoint(plugin, 'oauth_provider.token').invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(body: request),
              )
              as Map<String, dynamic>;
      expect(response['access_token'], isNotEmpty);
    });

    test('authorization endpoint rejects plain PKCE', () async {
      await expectLater(
        _endpoint(plugin, 'oauth_provider.authorize').invoke(
          AuthOperationInvocation<Object>(
            context: Object(),
            user: AuthUser(id: 'user-1'),
          ),
          AuthEndpointRequest(
            query: const <String, dynamic>{
              'client_id': 'client-1',
              'redirect_uri': 'https://client.example.test/callback',
              'response_type': 'code',
              'scope': 'openid',
              'code_challenge': _verifier,
              'code_challenge_method': 'plain',
            },
          ),
        ),
        _flow('invalid_request'),
      );
    });
  });

  group('OAuthProviderModePlugin security boundaries', () {
    test(
      'declares atomic single-use semantics only for a code-only endpoint',
      () {
        OAuthProviderModePlugin<Object> provider(List<String> grants) =>
            OAuthProviderModePlugin<Object>(
              clientStore: InMemoryOAuthClientStore(),
              authorizationCodeExchangeStore:
                  InMemoryOAuthAuthorizationCodeExchangeStore(),
              options: OAuthProviderModeOptions(supportedGrantTypes: grants),
            );

        final codeOnly =
            _endpoint(
                  provider(const ['authorization_code']),
                  'oauth_provider.token',
                ).semantics
                as AuthMutationOperationSemantics;
        expect(codeOnly.persistence.atomicity, AuthMutationAtomicity.atomic);
        expect(
          codeOnly.persistence.reference?.atomicOperationId,
          'exchangeCode',
        );
        expect(codeOnly.replaySafety, AuthMutationReplaySafety.singleUse);

        final mixed =
            _endpoint(
                  provider(const ['authorization_code', 'client_credentials']),
                  'oauth_provider.token',
                ).semantics
                as AuthMutationOperationSemantics;
        expect(mixed.persistence.atomicity, AuthMutationAtomicity.nonAtomic);
        expect(mixed.replaySafety, AuthMutationReplaySafety.unguarded);
      },
    );

    test('OAuth-only mode neither advertises nor grants openid', () async {
      final clients = InMemoryOAuthClientStore();
      await clients.create(
        OAuthClient(
          clientId: 'client-1',
          clientSecretHash: sha256.convert(utf8.encode('secret')).toString(),
          name: 'OAuth client',
          redirectUris: const ['https://client.example.test/callback'],
          scopes: const ['openid', 'api:read'],
        ),
      );
      final plugin = OAuthProviderModePlugin<Object>(
        clientStore: clients,
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
              authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
              accessTokenStore: InMemoryOAuthAccessTokenStore(),
            ),
        options: const OAuthProviderModeOptions(
          supportedScopes: ['openid', 'api:read'],
        ),
      )..configure(AuthServerPluginContext<Object>(store: InMemoryAuthStore()));

      expect(
        plugin.endpoints.map((endpoint) => endpoint.id),
        isNot(contains('oauth_provider.discovery')),
      );
      expect(
        plugin.endpoints.map((endpoint) => endpoint.id),
        isNot(contains('oauth_provider.jwks')),
      );
      await expectLater(
        _endpoint(plugin, 'oauth_provider.authorize').invoke(
          AuthOperationInvocation<Object>(
            context: Object(),
            user: AuthUser(id: 'user-1'),
          ),
          AuthEndpointRequest(
            query: const <String, dynamic>{
              'client_id': 'client-1',
              'redirect_uri': 'https://client.example.test/callback',
              'response_type': 'code',
              'scope': 'openid',
              'code_challenge': _challenge,
              'code_challenge_method': 'S256',
            },
          ),
        ),
        _flow('invalid_scope'),
      );
    });

    test('client credentials cannot mint an end-user ID token', () async {
      final authStore = InMemoryAuthStore();
      final clients = InMemoryOAuthClientStore();
      await clients.create(
        OAuthClient(
          clientId: 'service-client',
          clientSecretHash: sha256.convert(utf8.encode('secret')).toString(),
          name: 'Service client',
          redirectUris: const [],
          grantTypes: const ['client_credentials'],
          scopes: const ['openid'],
        ),
      );
      final plugin = OAuthProviderModePlugin<Object>(
        clientStore: clients,
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
              authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
              accessTokenStore: InMemoryOAuthAccessTokenStore(),
            ),
        options: OAuthProviderModeOptions(
          oidc: OAuthOidcConfiguration(
            issuer: Uri.parse('https://issuer.example.test'),
            signingKey: JsonWebKey.fromPem(_privateKeyPem, keyId: 'oidc-key-1'),
            signingAlgorithm: 'ES256',
          ),
        ),
      )..configure(AuthServerPluginContext<Object>(store: authStore));

      await expectLater(
        _endpoint(plugin, 'oauth_provider.token').invoke(
          AuthOperationInvocation<Object>(context: Object(), user: null),
          AuthEndpointRequest(
            body: const <String, dynamic>{
              'grant_type': 'client_credentials',
              'client_id': 'service-client',
              'client_secret': 'secret',
              'scope': 'openid',
            },
          ),
        ),
        _flow('invalid_scope'),
      );
    });

    test(
      'authorization codes are hash-only and binding failures consume',
      () async {
        final store = InMemoryOAuthAuthorizationCodeStore();
        final now = DateTime.now().toUtc();
        final record = OAuthAuthorizationCode(
          authorizationId: 'authorization-binding-test',
          codeHash: hashOpaqueToken('raw-code'),
          clientId: 'client-1',
          userId: 'user-1',
          redirectUri: 'https://client.example.test/callback',
          scope: 'api:read',
          expiresAt: now.add(const Duration(minutes: 5)),
          codeChallenge: _challenge,
          codeChallengeMethod: 'S256',
          createdAt: now,
        );
        await store.create(record);

        expect(record.toStorageJson().toString(), isNot(contains('raw-code')));
        expect(
          await store.consume(
            codeHash: hashOpaqueToken('raw-code'),
            clientId: 'other-client',
            redirectUri: 'https://client.example.test/callback',
            codeVerifier: _verifier,
          ),
          isNull,
        );
        expect(
          await store.consume(
            codeHash: hashOpaqueToken('raw-code'),
            clientId: 'client-1',
            redirectUri: 'https://client.example.test/callback',
            codeVerifier: _verifier,
          ),
          isNull,
        );
      },
    );

    test('OIDC rejects symmetric signing keys that JWKS cannot publish', () {
      expect(
        () => OAuthOidcConfiguration(
          issuer: Uri.parse('https://issuer.example.test'),
          signingKey: JsonWebKey.fromJson(<String, dynamic>{
            'kty': 'oct',
            'kid': 'symmetric-key',
            'k': base64Url.encode(utf8.encode('secret')).replaceAll('=', ''),
          }),
          signingAlgorithm: 'HS256',
        ),
        throwsArgumentError,
      );
    });

    test('user revocation removes pending codes and active tokens', () async {
      final codeStore = InMemoryOAuthAuthorizationCodeStore();
      final tokenStore = InMemoryOAuthAccessTokenStore();
      final plugin = OAuthProviderModePlugin<Object>(
        clientStore: InMemoryOAuthClientStore(),
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
              authorizationCodeStore: codeStore,
              accessTokenStore: tokenStore,
            ),
      );
      final now = DateTime.now().toUtc();
      await codeStore.create(
        OAuthAuthorizationCode(
          authorizationId: 'authorization-delete-user',
          codeHash: hashOpaqueToken('pending-code'),
          clientId: 'client-1',
          userId: 'user-1',
          redirectUri: 'https://client.example.test/callback',
          scope: 'api:read',
          expiresAt: now.add(const Duration(minutes: 5)),
          createdAt: now,
        ),
      );
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('access-token'),
          clientId: 'client-1',
          userId: 'user-1',
          scope: 'api:read',
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );

      await plugin.revokeUserAccess('user-1');

      expect(await tokenStore.findByToken('access-token'), isNull);
      expect(
        await codeStore.consume(
          codeHash: hashOpaqueToken('pending-code'),
          clientId: 'client-1',
          redirectUri: 'https://client.example.test/callback',
          codeVerifier: null,
        ),
        isNull,
      );
    });

    test('coordinated hard deletion removes both credential stores', () async {
      final core = InMemoryAuthStore();
      final codeStore = InMemoryOAuthAuthorizationCodeStore();
      final tokenStore = InMemoryOAuthAccessTokenStore();
      final plugin = OAuthProviderModePlugin<Object>(
        clientStore: InMemoryOAuthClientStore(),
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
              authorizationCodeStore: codeStore,
              accessTokenStore: tokenStore,
            ),
      );
      final now = DateTime.now().toUtc();
      await core.users.create(AuthUser(id: 'user-1'));
      plugin.configure(AuthServerPluginContext<Object>(store: core));
      await codeStore.create(
        OAuthAuthorizationCode(
          authorizationId: 'authorization-delete-client',
          codeHash: hashOpaqueToken('pending-code'),
          clientId: 'client-1',
          userId: 'user-1',
          redirectUri: 'https://client.example.test/callback',
          scope: 'api:read',
          expiresAt: now.add(const Duration(minutes: 5)),
          createdAt: now,
        ),
      );
      await tokenStore.save(
        OAuthAccessToken(
          tokenHash: hashOpaqueToken('access-token'),
          clientId: 'client-1',
          userId: 'user-1',
          scope: 'api:read',
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      core.bindUserDeletionPlanContributors([plugin]);
      expect(await core.userDeletionCoordinator.deleteUser('user-1'), isTrue);

      expect(await tokenStore.findByToken('access-token'), isNull);
      expect(
        await codeStore.consume(
          codeHash: hashOpaqueToken('pending-code'),
          clientId: 'client-1',
          redirectUri: 'https://client.example.test/callback',
          codeVerifier: null,
        ),
        isNull,
      );
    });
  });
}

AuthEndpointDescriptor<Object> _endpoint(
  OAuthProviderModePlugin<Object> plugin,
  String id,
) => plugin.endpoints.singleWhere((endpoint) => endpoint.id == id);

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);
