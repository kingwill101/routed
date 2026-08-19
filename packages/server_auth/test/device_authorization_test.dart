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

    test('claim is client-bound and can only succeed once', () async {
      final store = InMemoryAuthDeviceAuthorizationStore();
      await store.create(record());
      await store.approve(
        record().userCodeHash,
        'user-1',
        now: createdAt.add(const Duration(seconds: 1)),
      );

      expect(
        await store.claimApproved(
          record().deviceCodeHash,
          clientId: 'other-client',
          now: createdAt.add(const Duration(seconds: 2)),
        ),
        isNull,
      );
      final claimed = await store.claimApproved(
        record().deviceCodeHash,
        clientId: 'cli-1',
        now: createdAt.add(const Duration(seconds: 2)),
      );
      expect(claimed!.status, AuthDeviceAuthorizationStatus.consumed);
      expect(
        await store.claimApproved(
          record().deviceCodeHash,
          clientId: 'cli-1',
          now: createdAt.add(const Duration(seconds: 3)),
        ),
        isNull,
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
        issueToken:
            ({
              required context,
              required user,
              required clientId,
              required scopes,
              required authorizationId,
            }) {
              issued.add(authorizationId);
              return AuthDeviceAccessToken(
                accessToken: 'access-token',
                expiresIn: const Duration(minutes: 5),
                scopes: scopes,
              );
            },
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
        issueToken:
            ({
              required context,
              required user,
              required clientId,
              required scopes,
              required authorizationId,
            }) => AuthDeviceAccessToken(
              accessToken: 'unused',
              expiresIn: const Duration(minutes: 5),
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
  });
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);
