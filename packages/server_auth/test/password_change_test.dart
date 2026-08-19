import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

Argon2idPasswordHasher _testHasher() =>
    Argon2idPasswordHasher(iterations: 1, memoryKiB: 8, derivedKeyLength: 16);

void main() {
  test(
    'reauthenticates, replaces the password, and revokes sessions',
    () async {
      final store = InMemoryAuthStore();
      final hasher = _testHasher();
      final user = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: CredentialsProvider(),
        context: Object(),
        credentials: AuthCredentials(
          email: 'USER@example.com',
          password: 'old-password-123',
        ),
      );
      expect(user, isNotNull);

      final now = DateTime.utc(2030);
      await store.sessions.create(
        AuthSessionRecord(
          id: 'session-1',
          tokenHash: hashOpaqueToken('session-token-1'),
          userId: user!.id,
          createdAt: now,
          expiresAt: now.add(const Duration(days: 30)),
          lastUsedAt: now,
          authenticationMethod: 'credentials',
        ),
      );
      await store.sessions.create(
        AuthSessionRecord(
          id: 'session-2',
          tokenHash: hashOpaqueToken('session-token-2'),
          userId: user.id,
          createdAt: now,
          expiresAt: now.add(const Duration(days: 30)),
          lastUsedAt: now,
          authenticationMethod: 'credentials',
        ),
      );

      final result = await changeAuthPasswordForUser(
        store: store,
        passwordHasher: hasher,
        userId: user.id,
        identifier: ' user@example.com ',
        currentPassword: 'old-password-123',
        newPassword: 'new-password-456',
        now: now,
      );

      expect(result.credentialsUpdated, 1);
      expect(result.sessionsRevoked, 2);
      expect(await store.jwtVersions.current(user.id), equals(1));
      final credential = await store.credentials.findByIdentifier(
        'user@example.com',
      );
      expect(credential, isNotNull);
      expect(
        hasher.verify('old-password-123', credential!.passwordHash).matches,
        isFalse,
      );
      expect(
        hasher.verify('new-password-456', credential.passwordHash).matches,
        isTrue,
      );
      expect(
        (await store.sessions.find(
          hashOpaqueToken('session-token-1'),
        ))?.revokedAt,
        isNotNull,
      );
    },
  );

  test('password change revokes trusted-device bypass tokens', () async {
    final store = InMemoryAuthStore();
    final hasher = _testHasher();
    final user = await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'user@example.com',
        password: 'old-password-123',
      ),
    );
    final trustedDeviceStore = InMemoryAuthTwoFactorTrustedDeviceStore();
    final now = DateTime.utc(2030);
    trustedDeviceStore.create(
      AuthTwoFactorTrustedDeviceRecord(
        id: 'trusted-1',
        userId: user!.id,
        tokenHash: hashOpaqueToken('old-device-token'),
        createdAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      ),
    );

    await changeAuthPasswordForUser(
      store: store,
      passwordHasher: hasher,
      userId: user.id,
      identifier: 'user@example.com',
      currentPassword: 'old-password-123',
      newPassword: 'new-password-456',
      trustedDeviceStore: trustedDeviceStore,
      now: now,
    );

    expect(
      trustedDeviceStore.findActive(
        user.id,
        hashOpaqueToken('old-device-token'),
        now: now,
      ),
      isNull,
    );
  });

  test('rejects an identifier that belongs to another user', () async {
    final store = InMemoryAuthStore();
    final hasher = _testHasher();
    final first = await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'first@example.com',
        password: 'first-password-123',
      ),
    );
    final second = await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'second@example.com',
        password: 'second-password-123',
      ),
    );

    expect(
      () => changeAuthPasswordForUser(
        store: store,
        passwordHasher: hasher,
        userId: first!.id,
        identifier: second!.email!,
        currentPassword: 'second-password-123',
        newPassword: 'new-password-456',
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'invalid_current_password',
        ),
      ),
    );
  });
}
