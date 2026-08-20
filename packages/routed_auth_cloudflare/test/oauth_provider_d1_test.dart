import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('Cloudflare D1 OAuth provider persistence', () {
    test('passes the public authorization-code exchange conformance', () async {
      final databases = <FakeCloudflareD1Database>[];
      addTearDown(() {
        for (final database in databases) {
          database.close();
        }
      });

      await verifyOAuthAuthorizationCodeExchangeStoreConformance(() async {
        final database = FakeCloudflareD1Database();
        databases.add(database);
        final store = await CloudflareD1AuthStore.open(database);
        return store.oauthAuthorizationCodeExchangeStore;
      });
    });

    test('rolls back a failed exchange and permits one retry', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(database, schema: schema);
      final fixture = await _createExchangeFixture(store, 'rollback');

      var injected = false;
      database.batchFaultInjector = (statementIndex, _) {
        if (!injected && statementIndex == 0) {
          injected = true;
          throw StateError('injected D1 exchange failure');
        }
      };

      await expectLater(
        store.oauthAuthorizationCodeExchangeStore.commit(
          request: fixture.request,
          expectedAuthorizationId: fixture.code.authorizationId,
          preparedToken: fixture.token,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        database.select(
          'SELECT * FROM ${schema.table('oauth_authorization_codes')}',
        ),
        hasLength(1),
      );
      expect(
        database.select('SELECT * FROM ${schema.table('oauth_access_tokens')}'),
        isEmpty,
      );

      database.batchFaultInjector = null;
      expect(
        (await store.oauthAuthorizationCodeExchangeStore.prepare(
          fixture.request,
        )).status,
        OAuthAuthorizationCodePreparationStatus.ready,
      );
      expect(
        (await store.oauthAuthorizationCodeExchangeStore.commit(
          request: fixture.request,
          expectedAuthorizationId: fixture.code.authorizationId,
          preparedToken: fixture.token,
        )).status,
        OAuthAuthorizationCodeExchangeStatus.committed,
      );
      expect(
        database.select(
          'SELECT * FROM ${schema.table('oauth_authorization_codes')}',
        ),
        isEmpty,
      );
      expect(
        database.select('SELECT * FROM ${schema.table('oauth_access_tokens')}'),
        hasLength(1),
      );
    });

    test('persists only client, code, and token digests', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(database, schema: schema);
      const rawClientSecret = 'raw-client-secret-do-not-store';
      final client = OAuthClient(
        clientId: 'digest-client',
        clientSecretHash: hashOpaqueToken(rawClientSecret),
        name: 'Digest client',
        redirectUris: const ['https://digest.example.test/callback'],
        grantTypes: const ['authorization_code', 'refresh_token'],
      );
      await store.oauthClientStore.create(client);
      final fixture = await _createExchangeFixture(store, 'digest');

      expect(
        await store.oauthClientStore.validateSecret(
          client.clientId,
          rawClientSecret,
        ),
        isTrue,
      );
      expect(
        (await store.oauthAuthorizationCodeExchangeStore.commit(
          request: fixture.request,
          expectedAuthorizationId: fixture.code.authorizationId,
          preparedToken: fixture.token,
        )).status,
        OAuthAuthorizationCodeExchangeStatus.committed,
      );
      expect(
        await store.oauthAccessTokenStore.findByToken(fixture.rawAccessToken),
        isNotNull,
      );
      expect(
        await store.oauthAccessTokenStore.findByRefreshToken(
          fixture.rawRefreshToken,
        ),
        isNotNull,
      );

      final persisted = [
        ...database.select('SELECT * FROM ${schema.table('oauth_clients')}'),
        ...database.select(
          'SELECT * FROM ${schema.table('oauth_authorization_codes')}',
        ),
        ...database.select(
          'SELECT * FROM ${schema.table('oauth_access_tokens')}',
        ),
      ].expand((row) => row.values).whereType<String>().join('\n');
      expect(persisted, isNot(contains(rawClientSecret)));
      expect(persisted, isNot(contains(fixture.rawCode)));
      expect(persisted, isNot(contains(fixture.rawAccessToken)));
      expect(persisted, isNot(contains(fixture.rawRefreshToken)));
      expect(persisted, contains(hashOpaqueToken(rawClientSecret)));
      expect(persisted, contains(hashOpaqueToken(fixture.rawAccessToken)));
      expect(persisted, contains(hashOpaqueToken(fixture.rawRefreshToken)));
    });

    test('rotates one refresh token under contention', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(database);
      const rawAccessToken = 'initial-access-token';
      const rawRefreshToken = 'initial-refresh-token';
      const replacementAccessToken = 'replacement-access-token';
      const replacementRefreshToken = 'replacement-refresh-token';
      final initial = OAuthAccessToken(
        tokenHash: hashOpaqueToken(rawAccessToken),
        authorizationId: 'refresh-authorization',
        clientId: 'refresh-client',
        userId: 'refresh-user',
        scope: 'profile',
        expiresAt: DateTime.utc(2030, 1, 1, 1),
        refreshTokenHash: hashOpaqueToken(rawRefreshToken),
        refreshTokenExpiresAt: DateTime.utc(2030, 1, 2),
        issuedAt: DateTime.utc(2030, 1, 1),
      );
      final replacement = OAuthAccessToken(
        tokenHash: hashOpaqueToken(replacementAccessToken),
        authorizationId: initial.authorizationId,
        clientId: initial.clientId,
        userId: initial.userId,
        scope: initial.scope,
        expiresAt: DateTime.utc(2030, 1, 1, 2),
        refreshTokenHash: hashOpaqueToken(replacementRefreshToken),
        refreshTokenExpiresAt: initial.refreshTokenExpiresAt,
        refreshTokenUses: 1,
        issuedAt: DateTime.utc(2030, 1, 1, 1),
      );
      await store.oauthAccessTokenStore.save(initial);

      final results = await Future.wait([
        for (var index = 0; index < 16; index++)
          store.oauthAccessTokenStore.rotateRefreshToken(
            refreshToken: rawRefreshToken,
            expectedTokenHash: initial.tokenHash,
            replacement: replacement,
            maxUses: 4,
          ),
      ]);

      expect(results.whereType<OAuthAccessToken>(), hasLength(1));
      expect(
        await store.oauthAccessTokenStore.findByToken(rawAccessToken),
        isNull,
      );
      expect(
        await store.oauthAccessTokenStore.findByRefreshToken(rawRefreshToken),
        isNull,
      );
      expect(
        await store.oauthAccessTokenStore.findByToken(replacementAccessToken),
        isNotNull,
      );
    });

    test('runs a complete provider code grant on D1', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      const schema = CloudflareD1AuthSchema();
      final store = await CloudflareD1AuthStore.open(database, schema: schema);
      final user = AuthUser(
        id: 'provider-user',
        email: 'provider@example.test',
      );
      await store.users.create(user);
      await store.oauthClientStore.create(
        OAuthClient(
          clientId: 'provider-client',
          clientSecretHash: hashOpaqueToken('provider-secret'),
          name: 'Provider client',
          redirectUris: const ['https://provider.example.test/callback'],
          grantTypes: const ['authorization_code', 'refresh_token'],
          scopes: const ['profile'],
        ),
      );
      final provider = OAuthProviderModePlugin<Object>(
        clientStore: store.oauthClientStore,
        authorizationCodeExchangeStore:
            store.oauthAuthorizationCodeExchangeStore,
        options: const OAuthProviderModeOptions(supportedScopes: ['profile']),
      )..configure(AuthServerPluginContext<Object>(store: store));
      final authorize = provider.endpoints.singleWhere(
        (endpoint) => endpoint.id == 'oauth_provider.authorize',
      );
      final token = provider.endpoints.singleWhere(
        (endpoint) => endpoint.id == 'oauth_provider.token',
      );

      final redirect =
          await authorize.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: user),
                AuthEndpointRequest(
                  query: const <String, dynamic>{
                    'client_id': 'provider-client',
                    'redirect_uri': 'https://provider.example.test/callback',
                    'response_type': 'code',
                    'scope': 'profile',
                    'code_challenge':
                        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
                    'code_challenge_method': 'S256',
                  },
                ),
              )
              as AuthEndpointRedirect;
      final rawCode = redirect.location.queryParameters['code']!;
      final response =
          await token.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                AuthEndpointRequest(
                  body: <String, dynamic>{
                    'grant_type': 'authorization_code',
                    'client_id': 'provider-client',
                    'client_secret': 'provider-secret',
                    'redirect_uri': 'https://provider.example.test/callback',
                    'code': rawCode,
                    'code_verifier':
                        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
                  },
                ),
              )
              as Map<String, dynamic>;
      final rawAccessToken = response['access_token']! as String;

      expect(response['token_type'], 'Bearer');
      expect(response['refresh_token'], isA<String>());
      expect(
        await store.oauthAccessTokenStore.findByToken(rawAccessToken),
        isNotNull,
      );
      expect(
        database
            .select(
              'SELECT * FROM ${schema.table('oauth_authorization_codes')}',
            )
            .expand((row) => row.values)
            .whereType<String>(),
        isNot(contains(rawCode)),
      );
      expect(
        database
            .select('SELECT * FROM ${schema.table('oauth_access_tokens')}')
            .expand((row) => row.values)
            .whereType<String>(),
        isNot(contains(rawAccessToken)),
      );
    });

    test('requires one D1 domain for durable provider mode', () async {
      final firstDatabase = FakeCloudflareD1Database();
      final secondDatabase = FakeCloudflareD1Database();
      addTearDown(firstDatabase.close);
      addTearDown(secondDatabase.close);
      final first = await CloudflareD1AuthStore.open(firstDatabase);
      final second = await CloudflareD1AuthStore.open(secondDatabase);
      final provider = OAuthProviderModePlugin<Object>(
        clientStore: first.oauthClientStore,
        authorizationCodeExchangeStore:
            first.oauthAuthorizationCodeExchangeStore,
      );

      expect(
        () => provider.configure(AuthServerPluginContext<Object>(store: first)),
        returnsNormally,
      );
      expect(provider.validateProductionPosture, returnsNormally);

      final splitProvider = OAuthProviderModePlugin<Object>(
        clientStore: first.oauthClientStore,
        authorizationCodeExchangeStore:
            second.oauthAuthorizationCodeExchangeStore,
      );
      expect(
        () => splitProvider.configure(
          AuthServerPluginContext<Object>(store: first),
        ),
        throwsStateError,
      );
      expect(splitProvider.validateProductionPosture, throwsStateError);
    });
  });
}

Future<
  ({
    OAuthAuthorizationCode code,
    OAuthAuthorizationCodeExchangeRequest request,
    OAuthAccessToken token,
    String rawCode,
    String rawAccessToken,
    String rawRefreshToken,
  })
>
_createExchangeFixture(CloudflareD1AuthStore store, String namespace) async {
  const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  final rawCode = '$namespace-raw-code';
  final rawAccessToken = '$namespace-raw-access-token';
  final rawRefreshToken = '$namespace-raw-refresh-token';
  final code = OAuthAuthorizationCode(
    authorizationId: '$namespace-authorization',
    codeHash: hashOpaqueToken(rawCode),
    clientId: '$namespace-client',
    userId: '$namespace-user',
    redirectUri: 'https://$namespace.example.test/callback',
    scope: 'profile',
    expiresAt: DateTime.utc(2030, 1, 1, 0, 10),
    codeChallenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    codeChallengeMethod: 'S256',
    createdAt: DateTime.utc(2030, 1, 1),
  );
  final request = OAuthAuthorizationCodeExchangeRequest(
    codeHash: code.codeHash,
    clientId: code.clientId,
    redirectUri: code.redirectUri,
    codeVerifier: verifier,
    now: DateTime.utc(2030, 1, 1),
  );
  final token = OAuthAccessToken(
    tokenHash: hashOpaqueToken(rawAccessToken),
    authorizationId: code.authorizationId,
    clientId: code.clientId,
    userId: code.userId,
    scope: code.scope,
    expiresAt: DateTime.utc(2030, 1, 1, 1),
    refreshTokenHash: hashOpaqueToken(rawRefreshToken),
    refreshTokenExpiresAt: DateTime.utc(2030, 1, 2),
    issuedAt: DateTime.utc(2030, 1, 1),
  );
  await store.oauthAuthorizationCodeStore.create(code);
  return (
    code: code,
    request: request,
    token: token,
    rawCode: rawCode,
    rawAccessToken: rawAccessToken,
    rawRefreshToken: rawRefreshToken,
  );
}
