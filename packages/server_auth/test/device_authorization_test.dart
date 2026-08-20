import 'dart:async';
import 'dart:convert';

import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryAuthDeviceAuthorizationStore', () {
    final createdAt = DateTime.utc(2026, 1, 1, 12);

    AuthDeviceAuthorization record({
      AuthDeviceAuthorizationStatus status =
          AuthDeviceAuthorizationStatus.pending,
      String? userId,
    }) {
      return AuthDeviceAuthorization(
        id: 'authorization-1',
        deviceCodeHash: hashAuthDeviceAuthorizationCode('device-secret'),
        userCodeHash: hashAuthDeviceAuthorizationCode('ABCD2345'),
        clientId: 'cli-1',
        scopes: const ['openid', 'profile'],
        createdAt: createdAt,
        expiresAt: createdAt.add(const Duration(minutes: 10)),
        interval: const Duration(seconds: 5),
        status: status,
        userId: userId,
      );
    }

    test(
      'stores digests and never serializes raw authorization codes',
      () async {
        final store = InMemoryAuthDeviceAuthorizationStore();
        final value = record();

        await store.create(value);

        expect(value.deviceCodeHash, isNot('device-secret'));
        expect(value.userCodeHash, isNot('ABCD2345'));
        final json = value.toStorageJson();
        expect(json.values, isNot(contains('device-secret')));
        expect(json.values, isNot(contains('ABCD2345')));
        expect(json.keys, isNot(contains('deviceCode')));
        expect(json.keys, isNot(contains('userCode')));
      },
    );

    test('property: codes and lease identities remain digest-only', () async {
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 0, maxLength: 512),
        (value) {
          final rawDevice =
              'RAW_DEVICE_${base64Url.encode(utf8.encode(value))}';
          final rawUser = 'RAW_USER_${base64Url.encode(utf8.encode(value))}';
          final rawLease = 'RAW_LEASE_${base64Url.encode(utf8.encode(value))}';
          final authorization = AuthDeviceAuthorization(
            id: 'authorization-property',
            deviceCodeHash: hashAuthDeviceAuthorizationCode(rawDevice),
            userCodeHash: hashAuthDeviceAuthorizationCode(rawUser),
            clientId: 'cli-1',
            scopes: const <String>['openid'],
            createdAt: createdAt,
            expiresAt: createdAt.add(const Duration(minutes: 10)),
            interval: const Duration(seconds: 5),
            status: AuthDeviceAuthorizationStatus.approved,
            userId: 'user-1',
            issuanceLeaseDigest: hashAuthDeviceAuthorizationIssuanceLease(
              rawLease,
            ),
            issuanceLeaseExpiresAt: createdAt.add(const Duration(seconds: 30)),
          );
          final encoded = jsonEncode(authorization.toStorageJson());
          expect(encoded, isNot(contains(rawDevice)));
          expect(encoded, isNot(contains(rawUser)));
          expect(encoded, isNot(contains(rawLease)));
          expect(encoded, isNot(contains('access_token')));
          expect(encoded, isNot(contains('refresh_token')));
        },
        PropertyConfig(numTests: 500, seed: 20260820),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.error?.toString());
    });

    test(
      'enforces polling interval and increases it after early polling',
      () async {
        final store = InMemoryAuthDeviceAuthorizationStore();
        await store.create(record());

        final first = await store.poll(
          record().deviceCodeHash,
          now: createdAt.add(const Duration(seconds: 1)),
        );
        final early = await store.poll(
          record().deviceCodeHash,
          now: createdAt.add(const Duration(seconds: 2)),
        );
        final stillEarly = await store.poll(
          record().deviceCodeHash,
          now: createdAt.add(const Duration(seconds: 6)),
        );
        final later = await store.poll(
          record().deviceCodeHash,
          now: createdAt.add(const Duration(seconds: 18)),
        );

        expect(first.status, AuthDeviceAuthorizationPollStatus.pending);
        expect(early.status, AuthDeviceAuthorizationPollStatus.slowDown);
        expect(early.authorization!.interval, const Duration(seconds: 10));
        expect(stillEarly.status, AuthDeviceAuthorizationPollStatus.slowDown);
        expect(later.status, AuthDeviceAuthorizationPollStatus.pending);
      },
    );

    test('approval and denial are terminal single transitions', () async {
      final store = InMemoryAuthDeviceAuthorizationStore();
      await store.create(record());

      final approved = await store.approve(
        record().userCodeHash,
        'user-1',
        now: createdAt.add(const Duration(seconds: 1)),
      );
      expect(approved!.status, AuthDeviceAuthorizationStatus.approved);
      expect(await store.deny(record().userCodeHash, now: createdAt), isNull);

      final second = AuthDeviceAuthorization(
        id: 'authorization-2',
        deviceCodeHash: hashAuthDeviceAuthorizationCode('device-secret-2'),
        userCodeHash: hashAuthDeviceAuthorizationCode('WXYZ6789'),
        clientId: 'cli-1',
        scopes: const [],
        createdAt: createdAt,
        expiresAt: createdAt.add(const Duration(minutes: 10)),
        interval: const Duration(seconds: 5),
      );
      await store.create(second);
      final denied = await store.deny(
        second.userCodeHash,
        now: createdAt.add(const Duration(seconds: 1)),
      );
      expect(denied!.status, AuthDeviceAuthorizationStatus.denied);
      expect(
        await store.approve(second.userCodeHash, 'user-2', now: createdAt),
        isNull,
      );
    });

    test('issuance leases are client-bound, bounded, and stale-safe', () async {
      final store = InMemoryAuthDeviceAuthorizationStore();
      await store.create(record());
      await store.approve(
        record().userCodeHash,
        'user-1',
        now: createdAt.add(const Duration(seconds: 1)),
      );

      expect(
        (await store.beginIssuance(
          record().deviceCodeHash,
          clientId: 'other-client',
          leaseDigest: 'wrong-client-lease',
          leaseExpiresAt: createdAt.add(const Duration(seconds: 30)),
          now: createdAt.add(const Duration(seconds: 2)),
        )).status,
        AuthDeviceAuthorizationIssuanceLeaseStatus.invalid,
      );
      final first = await store.beginIssuance(
        record().deviceCodeHash,
        clientId: 'cli-1',
        leaseDigest: 'lease-1',
        leaseExpiresAt: createdAt.add(const Duration(seconds: 30)),
        now: createdAt.add(const Duration(seconds: 2)),
      );
      expect(first.status, AuthDeviceAuthorizationIssuanceLeaseStatus.acquired);
      expect(
        (await store.beginIssuance(
          record().deviceCodeHash,
          clientId: 'cli-1',
          leaseDigest: 'lease-2',
          leaseExpiresAt: createdAt.add(const Duration(seconds: 40)),
          now: createdAt.add(const Duration(seconds: 3)),
        )).status,
        AuthDeviceAuthorizationIssuanceLeaseStatus.busy,
      );
      expect(
        await store.completeIssuance(
          record().deviceCodeHash,
          clientId: 'cli-1',
          leaseDigest: 'stale-lease',
          now: createdAt.add(const Duration(seconds: 4)),
        ),
        isFalse,
      );
      final recovered = await store.beginIssuance(
        record().deviceCodeHash,
        clientId: 'cli-1',
        leaseDigest: 'lease-2',
        leaseExpiresAt: createdAt.add(const Duration(seconds: 60)),
        now: createdAt.add(const Duration(seconds: 31)),
      );
      expect(
        recovered.status,
        AuthDeviceAuthorizationIssuanceLeaseStatus.acquired,
      );
      expect(
        await store.releaseIssuance(
          record().deviceCodeHash,
          clientId: 'cli-1',
          leaseDigest: 'lease-1',
          now: createdAt.add(const Duration(seconds: 32)),
        ),
        isFalse,
      );
      expect(
        await store.completeIssuance(
          record().deviceCodeHash,
          clientId: 'cli-1',
          leaseDigest: 'lease-2',
          now: createdAt.add(const Duration(seconds: 32)),
        ),
        isTrue,
      );
    });
  });

  group('DeviceAuthorizationPlugin', () {
    test('validates client, normalizes scopes, and issues one token', () async {
      final store = InMemoryAuthStore();
      final user = AuthUser(id: 'user-1', email: 'user@example.com');
      await store.users.create(user);
      final issued = <String>[];
      final feature = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (context, clientId, scopes) {
          expect(clientId, 'cli-1');
          expect(scopes, ['openid', 'profile']);
          return true;
        },
        tokenIssuer: _TestDeviceTokenIssuer((request) {
          issued.add(request.authorizationId);
          return AuthDeviceAccessToken(
            accessToken: 'access-token',
            expiresIn: const Duration(minutes: 5),
            scopes: request.scopes,
          );
        }),
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );

      final request = await feature.authorizeDevice(
        context: Object(),
        clientId: ' cli-1 ',
        scopes: const ['openid', 'profile', 'openid'],
        now: DateTime.utc(2026, 1, 1),
      );
      expect(request.userCode, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(request.toJson()['device_code'], request.deviceCode);

      await expectLater(
        feature.pollDeviceToken(
          context: Object(),
          clientId: 'cli-1',
          deviceCode: request.deviceCode,
          now: DateTime.utc(2026, 1, 1, 0, 0, 1),
        ),
        _flow('authorization_pending'),
      );
      await feature.approveDevice(
        userId: user.id,
        userCode: request.userCode,
        now: DateTime.utc(2026, 1, 1, 0, 0, 2),
      );
      final token = await feature.pollDeviceToken(
        context: Object(),
        clientId: 'cli-1',
        deviceCode: request.deviceCode,
        now: DateTime.utc(2026, 1, 1, 0, 0, 7),
      );

      expect(token.toJson(), {
        'access_token': 'access-token',
        'token_type': 'Bearer',
        'expires_in': 300,
        'scope': 'openid profile',
      });
      expect(issued, hasLength(1));
      await expectLater(
        feature.pollDeviceToken(
          context: Object(),
          clientId: 'cli-1',
          deviceCode: request.deviceCode,
          now: DateTime.utc(2026, 1, 1, 0, 0, 8),
        ),
        _flow('invalid_grant'),
      );
      expect(runtime.hasPlugin(authDeviceAuthorizationPluginId), isTrue);
    });

    test('rejects untrusted clients and invalid scopes', () async {
      final feature = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (context, clientId, scopes) => false,
        tokenIssuer: _TestDeviceTokenIssuer(
          (_) => const AuthDeviceAccessToken(
            accessToken: 'unused',
            expiresIn: Duration(minutes: 5),
          ),
        ),
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );

      await expectLater(
        feature.authorizeDevice(
          context: Object(),
          clientId: 'untrusted',
          scopes: const ['openid'],
        ),
        _flow('invalid_client'),
      );
      expect(runtime.registry.persistenceSchemas.single.entities, hasLength(1));
      await expectLater(
        feature.authorizeDevice(
          context: Object(),
          clientId: 'untrusted',
          scopes: const ['bad scope'],
        ),
        throwsA(isA<AuthFlowException>()),
      );
    });

    test(
      'retries an ambiguous issuer failure with one logical grant',
      () async {
        final store = InMemoryAuthStore();
        await store.users.create(AuthUser(id: 'user-1'));
        final issuer = _FaultAfterMintDeviceTokenIssuer<Object>();
        final feature = DeviceAuthorizationPlugin<Object>(
          verificationUri: 'https://example.test/device',
          validateClient: (_, _, _) => true,
          tokenIssuer: issuer,
          pollInterval: const Duration(seconds: 1),
          issuanceLeaseTtl: const Duration(seconds: 5),
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const [],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [feature],
          ),
        );
        final start = DateTime.utc(2026, 1, 1);
        final request = await feature.authorizeDevice(
          context: Object(),
          clientId: 'cli-1',
          scopes: const ['openid'],
          now: start,
        );
        await feature.approveDevice(
          userId: 'user-1',
          userCode: request.userCode,
          now: start.add(const Duration(seconds: 1)),
        );

        await expectLater(
          feature.pollDeviceToken(
            context: Object(),
            clientId: 'cli-1',
            deviceCode: request.deviceCode,
            now: start.add(const Duration(seconds: 2)),
          ),
          throwsStateError,
        );
        final token = await feature.pollDeviceToken(
          context: Object(),
          clientId: 'cli-1',
          deviceCode: request.deviceCode,
          now: start.add(const Duration(seconds: 4)),
        );

        expect(token.accessToken, startsWith('stable-token-'));
        expect(issuer.calls, 2);
        expect(issuer.mints, 1);
        expect(issuer.authorizationIds.toSet(), hasLength(1));
      },
    );

    test('recovers an abandoned issuance lease after expiry', () async {
      final store = InMemoryAuthStore();
      await store.users.create(AuthUser(id: 'user-1'));
      final feature = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (_, _, _) => true,
        tokenIssuer: _TestDeviceTokenIssuer(
          (request) => AuthDeviceAccessToken(
            accessToken: 'access-${request.authorizationId}',
            expiresIn: const Duration(minutes: 5),
          ),
        ),
        pollInterval: const Duration(seconds: 1),
        issuanceLeaseTtl: const Duration(seconds: 5),
      );
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );
      final start = DateTime.utc(2026, 1, 1);
      final request = await feature.authorizeDevice(
        context: Object(),
        clientId: 'cli-1',
        now: start,
      );
      await feature.approveDevice(
        userId: 'user-1',
        userCode: request.userCode,
        now: start.add(const Duration(seconds: 1)),
      );
      final abandoned = await store.deviceAuthorizations.beginIssuance(
        hashAuthDeviceAuthorizationCode(request.deviceCode),
        clientId: 'cli-1',
        leaseDigest: 'abandoned-lease-digest',
        leaseExpiresAt: start.add(const Duration(seconds: 3)),
        now: start.add(const Duration(seconds: 2)),
      );
      expect(
        abandoned.status,
        AuthDeviceAuthorizationIssuanceLeaseStatus.acquired,
      );

      final token = await feature.pollDeviceToken(
        context: Object(),
        clientId: 'cli-1',
        deviceCode: request.deviceCode,
        now: start.add(const Duration(seconds: 4)),
      );
      expect(token.accessToken, startsWith('access-'));
      expect(
        await store.deviceAuthorizations.releaseIssuance(
          hashAuthDeviceAuthorizationCode(request.deviceCode),
          clientId: 'cli-1',
          leaseDigest: 'abandoned-lease-digest',
          now: start.add(const Duration(seconds: 4)),
        ),
        isFalse,
      );
    });

    test('denial, expiry, and wrong-client polling fail safely', () async {
      final store = InMemoryAuthStore();
      await store.users.create(AuthUser(id: 'user-1'));
      final feature = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (_, _, _) => true,
        tokenIssuer: _TestDeviceTokenIssuer(
          (_) => const AuthDeviceAccessToken(
            accessToken: 'unused',
            expiresIn: Duration(minutes: 5),
          ),
        ),
        deviceCodeTtl: const Duration(seconds: 10),
        pollInterval: const Duration(seconds: 1),
      );
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );
      final start = DateTime.utc(2026, 1, 1);
      final denied = await feature.authorizeDevice(
        context: Object(),
        clientId: 'cli-1',
        now: start,
      );
      await feature.denyDevice(
        userCode: denied.userCode,
        now: start.add(const Duration(seconds: 1)),
      );
      await expectLater(
        feature.pollDeviceToken(
          context: Object(),
          clientId: 'cli-1',
          deviceCode: denied.deviceCode,
          now: start.add(const Duration(seconds: 2)),
        ),
        _flow('access_denied'),
      );

      final expired = await feature.authorizeDevice(
        context: Object(),
        clientId: 'cli-1',
        now: start,
      );
      await expectLater(
        feature.pollDeviceToken(
          context: Object(),
          clientId: 'cli-1',
          deviceCode: expired.deviceCode,
          now: start.add(const Duration(seconds: 11)),
        ),
        _flow('expired_token'),
      );

      final clientBound = await feature.authorizeDevice(
        context: Object(),
        clientId: 'cli-1',
        now: start,
      );
      await feature.approveDevice(
        userId: 'user-1',
        userCode: clientBound.userCode,
        now: start.add(const Duration(seconds: 1)),
      );
      await expectLater(
        feature.pollDeviceToken(
          context: Object(),
          clientId: 'other-client',
          deviceCode: clientBound.deviceCode,
          now: start.add(const Duration(seconds: 2)),
        ),
        _flow('invalid_grant'),
      );
    });

    test(
      'concurrent token polls mint and complete one logical grant',
      () async {
        final store = InMemoryAuthStore();
        await store.users.create(AuthUser(id: 'user-1'));
        final issuer = _CountingDeviceTokenIssuer<Object>();
        final feature = DeviceAuthorizationPlugin<Object>(
          verificationUri: 'https://example.test/device',
          validateClient: (_, _, _) => true,
          tokenIssuer: issuer,
          pollInterval: const Duration(seconds: 1),
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const [],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [feature],
          ),
        );
        final start = DateTime.utc(2026, 1, 1);
        final request = await feature.authorizeDevice(
          context: Object(),
          clientId: 'cli-1',
          now: start,
        );
        await feature.approveDevice(
          userId: 'user-1',
          userCode: request.userCode,
          now: start.add(const Duration(seconds: 1)),
        );

        final outcomes = await Future.wait([
          for (var index = 0; index < 16; index++)
            feature
                .pollDeviceToken(
                  context: Object(),
                  clientId: 'cli-1',
                  deviceCode: request.deviceCode,
                  now: start.add(const Duration(seconds: 2)),
                )
                .then<Object>((token) => token)
                .catchError((Object error) => error),
        ]);

        expect(outcomes.whereType<AuthDeviceAccessToken>(), hasLength(1));
        expect(
          outcomes.whereType<AuthFlowException>().every(
            (error) => const {
              'slow_down',
              'authorization_pending',
            }.contains(error.code),
          ),
          isTrue,
        );
        expect(issuer.calls, 1);
      },
    );

    test(
      'does not issue after the approving account becomes disabled',
      () async {
        final store = InMemoryAuthStore();
        await store.users.create(AuthUser(id: 'user-1'));
        var issued = false;
        final feature = DeviceAuthorizationPlugin<Object>(
          verificationUri: 'https://example.test/device',
          validateClient: (_, _, _) => true,
          tokenIssuer: _TestDeviceTokenIssuer((_) {
            issued = true;
            return const AuthDeviceAccessToken(
              accessToken: 'must-not-be-issued',
              expiresIn: Duration(minutes: 5),
            );
          }),
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const [],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [feature],
          ),
        );
        final request = await feature.authorizeDevice(
          context: Object(),
          clientId: 'cli-1',
          scopes: const ['openid'],
        );
        await feature.approveDevice(
          userId: 'user-1',
          userCode: request.userCode,
        );
        await store.disable('user-1', reason: 'security');

        await expectLater(
          feature.pollDeviceToken(
            context: Object(),
            clientId: 'cli-1',
            deviceCode: request.deviceCode,
          ),
          _flow('invalid_grant'),
        );
        expect(issued, isFalse);
      },
    );

    test(
      'does not deliver a token when the account is disabled mid-issue',
      () async {
        final store = InMemoryAuthStore();
        await store.users.create(AuthUser(id: 'user-1'));
        final feature = DeviceAuthorizationPlugin<Object>(
          verificationUri: 'https://example.test/device',
          validateClient: (_, _, _) => true,
          tokenIssuer: _TestDeviceTokenIssuer((_) async {
            await store.disable('user-1', reason: 'security');
            return const AuthDeviceAccessToken(
              accessToken: 'must-not-be-delivered',
              expiresIn: Duration(minutes: 5),
            );
          }),
          pollInterval: const Duration(seconds: 1),
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const [],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [feature],
          ),
        );
        final start = DateTime.utc(2026, 1, 1);
        final request = await feature.authorizeDevice(
          context: Object(),
          clientId: 'cli-1',
          now: start,
        );
        await feature.approveDevice(
          userId: 'user-1',
          userCode: request.userCode,
          now: start.add(const Duration(seconds: 1)),
        );

        await expectLater(
          feature.pollDeviceToken(
            context: Object(),
            clientId: 'cli-1',
            deviceCode: request.deviceCode,
            now: start.add(const Duration(seconds: 2)),
          ),
          _flow('invalid_grant'),
        );
      },
    );

    test('access revocation removes approved device grants', () async {
      final store = InMemoryAuthStore();
      await store.users.create(AuthUser(id: 'user-1'));
      final feature = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (_, _, _) => true,
        tokenIssuer: _TestDeviceTokenIssuer(
          (_) => const AuthDeviceAccessToken(
            accessToken: 'must-not-be-issued',
            expiresIn: Duration(minutes: 5),
          ),
        ),
      );
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );
      final request = await feature.authorizeDevice(
        context: Object(),
        clientId: 'cli-1',
        scopes: const ['openid'],
      );
      await feature.approveDevice(userId: 'user-1', userCode: request.userCode);

      await feature.revokeUserAccess('user-1');

      await expectLater(
        feature.pollDeviceToken(
          context: Object(),
          clientId: 'cli-1',
          deviceCode: request.deviceCode,
        ),
        _flow('invalid_grant'),
      );
    });

    test('shares one token endpoint with OAuth provider mode', () async {
      final store = InMemoryAuthStore();
      await store.users.create(AuthUser(id: 'user-1'));
      final device = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (_, _, _) => true,
        tokenIssuer: _TestDeviceTokenIssuer(
          (request) => AuthDeviceAccessToken(
            accessToken: 'device-access-token',
            expiresIn: const Duration(minutes: 5),
            scopes: request.scopes,
          ),
        ),
      );
      final provider = OAuthProviderModePlugin<Object>(
        clientStore: InMemoryOAuthClientStore(),
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
          authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
          accessTokenStore: InMemoryOAuthAccessTokenStore(),
        ),
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [provider, device],
        ),
      );
      final tokenEndpoints = runtime.registry.endpoints
          .where(
            (endpoint) =>
                endpoint.method == AuthOperationMethod.post &&
                endpoint.path == '/oauth/token',
          )
          .toList(growable: false);
      expect(tokenEndpoints, hasLength(1));
      final request = await device.authorizeDevice(
        context: Object(),
        clientId: 'cli-1',
        scopes: const ['openid'],
      );
      await device.approveDevice(userId: 'user-1', userCode: request.userCode);

      final response =
          await tokenEndpoints.single.invoke(
                AuthOperationInvocation<Object>(context: Object(), user: null),
                <String, dynamic>{
                  'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
                  'client_id': 'cli-1',
                  'device_code': request.deviceCode,
                },
              )
              as Map<String, dynamic>;
      expect(response['access_token'], 'device-access-token');
    });

    test('shares one token endpoint with authorization-code mode', () {
      final store = InMemoryAuthStore();
      final device = DeviceAuthorizationPlugin<Object>(
        verificationUri: 'https://example.test/device',
        validateClient: (_, _, _) => true,
        tokenIssuer: _TestDeviceTokenIssuer(
          (_) => const AuthDeviceAccessToken(
            accessToken: 'unused',
            expiresIn: Duration(minutes: 5),
          ),
        ),
      );
      final authorization = OAuthProviderModePlugin<Object>(
        clientStore: InMemoryOAuthClientStore(),
        authorizationCodeExchangeStore:
            InMemoryOAuthAuthorizationCodeExchangeStore(
          authorizationCodeStore: InMemoryOAuthAuthorizationCodeStore(),
          accessTokenStore: InMemoryOAuthAccessTokenStore(),
        ),
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [authorization, device],
        ),
      );

      expect(
        runtime.registry.endpoints.where(
          (endpoint) =>
              endpoint.method == AuthOperationMethod.post &&
              endpoint.path == '/oauth/token',
        ),
        hasLength(1),
      );
    });
  });
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);

final class _TestDeviceTokenIssuer<TContext>
    implements AuthDeviceAuthorizationTokenIssuer<TContext> {
  const _TestDeviceTokenIssuer(this.callback);

  final FutureOr<AuthDeviceAccessToken> Function(
    AuthDeviceAuthorizationTokenIssuanceRequest<TContext> request,
  )
  callback;

  @override
  FutureOr<AuthDeviceAccessToken> issue(
    AuthDeviceAuthorizationTokenIssuanceRequest<TContext> request,
  ) => callback(request);
}

final class _FaultAfterMintDeviceTokenIssuer<TContext>
    implements AuthDeviceAuthorizationTokenIssuer<TContext> {
  final Map<String, AuthDeviceAccessToken> _tokens = {};
  final List<String> authorizationIds = [];
  var calls = 0;
  var mints = 0;

  @override
  AuthDeviceAccessToken issue(
    AuthDeviceAuthorizationTokenIssuanceRequest<TContext> request,
  ) {
    calls++;
    authorizationIds.add(request.authorizationId);
    final token = _tokens.putIfAbsent(request.authorizationId, () {
      mints++;
      return AuthDeviceAccessToken(
        accessToken: 'stable-token-${request.authorizationId}',
        expiresIn: const Duration(minutes: 5),
        scopes: request.scopes,
      );
    });
    if (calls == 1) throw StateError('ambiguous issuer failure');
    return token;
  }
}

final class _CountingDeviceTokenIssuer<TContext>
    implements AuthDeviceAuthorizationTokenIssuer<TContext> {
  var calls = 0;

  @override
  AuthDeviceAccessToken issue(
    AuthDeviceAuthorizationTokenIssuanceRequest<TContext> request,
  ) {
    calls++;
    return AuthDeviceAccessToken(
      accessToken: 'token-${request.authorizationId}',
      expiresIn: const Duration(minutes: 5),
      scopes: request.scopes,
    );
  }
}
