import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

final _resetNow = DateTime.now().toUtc();

Argon2idPasswordHasher _testHasher() =>
    Argon2idPasswordHasher(iterations: 1, memoryKiB: 8, derivedKeyLength: 16);

Future<InMemoryAuthStore> _storeWithCredential({PasswordHasher? hasher}) async {
  final effectiveHasher = hasher ?? _testHasher();
  final store = InMemoryAuthStore();
  final user = AuthUser(id: 'user-1', email: 'user@example.com');
  await store.credentials.register(
    user,
    AuthPasswordCredential(
      id: 'credential-1',
      userId: user.id,
      identifier: user.email!,
      passwordHash: effectiveHasher.hash('old-password-123'),
      createdAt: _resetNow,
      updatedAt: _resetNow,
    ),
  );
  return store;
}

AuthSessionRecord _session(String id) => AuthSessionRecord(
  id: id,
  tokenHash: hashOpaqueToken(id),
  userId: 'user-1',
  createdAt: _resetNow,
  expiresAt: _resetNow.add(const Duration(hours: 1)),
  lastUsedAt: _resetNow,
  authenticationMethod: 'password',
);

void main() {
  test('issues and consumes a reset token to replace the password', () async {
    final hasher = _testHasher();
    final store = await _storeWithCredential(hasher: hasher);
    await store.sessions.create(_session('session-1'));
    await store.sessions.create(_session('session-2'));

    final token = await issueAuthPasswordResetTokenForUser(
      store: store,
      userId: 'user-1',
      ttl: const Duration(minutes: 10),
      generateToken: () => 'reset-secret',
      now: _resetNow,
    );

    final result = await resetAuthPasswordWithToken(
      store: store,
      passwordHasher: hasher,
      token: token!,
      newPassword: 'new-password-456',
      now: _resetNow,
    );

    expect(result.user.id, equals('user-1'));
    expect(result.credentialsUpdated, equals(1));
    expect(result.sessionsRevoked, equals(2));
    expect(await store.jwtVersions.current(result.user.id), equals(1));
    expect(await store.passwordResetTokens.consume(token), isNull);

    final provider = CredentialsProvider();
    expect(
      await authorizeCredentialsSignIn(
        store: store,
        passwordHasher: hasher,
        provider: provider,
        context: Object(),
        credentials: AuthCredentials(
          email: 'user@example.com',
          password: 'old-password-123',
        ),
      ),
      isNull,
    );
    expect(
      (await authorizeCredentialsSignIn(
        store: store,
        passwordHasher: hasher,
        provider: provider,
        context: Object(),
        credentials: AuthCredentials(
          email: 'user@example.com',
          password: 'new-password-456',
        ),
      ))?.id,
      equals('user-1'),
    );
  });

  test('password reset revokes trusted-device bypass tokens', () async {
    final hasher = _testHasher();
    final store = await _storeWithCredential(hasher: hasher);
    final trustedDeviceStore = InMemoryAuthTwoFactorTrustedDeviceStore();
    trustedDeviceStore.create(
      AuthTwoFactorTrustedDeviceRecord(
        id: 'trusted-1',
        userId: 'user-1',
        tokenHash: hashOpaqueToken('old-device-token'),
        createdAt: _resetNow,
        expiresAt: _resetNow.add(const Duration(days: 30)),
      ),
    );
    final token = await issueAuthPasswordResetTokenForUser(
      store: store,
      userId: 'user-1',
      ttl: const Duration(minutes: 10),
      generateToken: () => 'reset-with-device',
      now: _resetNow,
    );

    await resetAuthPasswordWithToken(
      store: store,
      passwordHasher: hasher,
      token: token!,
      newPassword: 'new-password-456',
      trustedDeviceStore: trustedDeviceStore,
      now: _resetNow,
    );

    expect(
      trustedDeviceStore.findActive(
        'user-1',
        hashOpaqueToken('old-device-token'),
        now: _resetNow,
      ),
      isNull,
    );
  });

  test('reset tokens cannot be used concurrently', () async {
    final hasher = _testHasher();
    final store = await _storeWithCredential(hasher: hasher);
    final token = await issueAuthPasswordResetTokenForUser(
      store: store,
      userId: 'user-1',
      ttl: const Duration(minutes: 10),
      generateToken: () => 'one-time-reset',
      now: _resetNow,
    );

    final results = await Future.wait(
      [
        resetAuthPasswordWithToken(
          store: store,
          passwordHasher: hasher,
          token: token!,
          newPassword: 'new-password-111',
          now: _resetNow,
        ),
        resetAuthPasswordWithToken(
          store: store,
          passwordHasher: hasher,
          token: token,
          newPassword: 'new-password-222',
          now: _resetNow,
        ),
      ].map(
        (future) =>
            future.then<Object?>((value) => value).catchError((_) => null),
      ),
    );

    expect(results.whereType<AuthPasswordResetResult>(), hasLength(1));
    expect(await store.passwordResetTokens.consume('one-time-reset'), isNull);
  });

  test('weak reset passwords fail before consuming the token', () async {
    final hasher = _testHasher();
    final store = await _storeWithCredential(hasher: hasher);
    final token = await issueAuthPasswordResetTokenForUser(
      store: store,
      userId: 'user-1',
      ttl: const Duration(minutes: 10),
      generateToken: () => 'retryable-reset',
      now: _resetNow,
    );

    await expectLater(
      resetAuthPasswordWithToken(
        store: store,
        passwordHasher: hasher,
        token: token!,
        newPassword: 'short',
        now: _resetNow,
      ),
      throwsA(
        isA<AuthFlowException>().having(
          (error) => error.code,
          'code',
          'password_too_short',
        ),
      ),
    );
    expect(await store.passwordResetTokens.consume(token), isNotNull);
  });

  test('issuing a reset token for an unknown user is non-issuing', () async {
    final result = await issueAuthPasswordResetTokenForUser(
      store: InMemoryAuthStore(),
      userId: 'missing-user',
      ttl: const Duration(minutes: 10),
      generateToken: () => 'must-not-be-stored',
      now: _resetNow,
    );

    expect(result, isNull);
  });
}
