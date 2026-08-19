import 'package:routed_auth/routed_auth.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryAuthStore', () {
    test(
      'registers and verifies credentials without exposing passwords',
      () async {
        final store = InMemoryAuthStore();
        final hasher = Argon2idPasswordHasher();

        final created = await authorizeCredentialsRegistration(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'user@example.com',
            password: 'test-password',
          ),
        );
        expect(created, isNotNull);
        expect(created?.attributes, isEmpty);

        expect(
          (await authorizeCredentialsSignIn(
            store: store,
            passwordHasher: hasher,
            provider: CredentialsProvider(),
            context: Object(),
            credentials: AuthCredentials(
              email: 'user@example.com',
              password: 'test-password',
            ),
          ))?.id,
          equals(created?.id),
        );
        expect(
          await authorizeCredentialsSignIn(
            store: store,
            passwordHasher: hasher,
            provider: CredentialsProvider(),
            context: Object(),
            credentials: AuthCredentials(
              email: 'user@example.com',
              password: 'wrong',
            ),
          ),
          isNull,
        );
        expect(
          await authorizeCredentialsRegistration(
            store: store,
            passwordHasher: hasher,
            provider: CredentialsProvider(),
            context: Object(),
            credentials: AuthCredentials(
              email: 'user@example.com',
              password: 'another',
            ),
          ),
          isNull,
        );
      },
    );

    test('stores users, accounts, sessions, and one-shot tokens', () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      expect(await store.users.findById(user.id), same(user));
      expect(await store.users.findByEmail(user.email!), same(user));

      final account = AuthAccount(
        providerId: 'github',
        providerAccountId: 'account-1',
        userId: user.id,
      );
      await store.accounts.link(account);
      expect(
        (await store.accounts.find('github', 'account-1'))?.userId,
        equals(user.id),
      );
      expect((await store.accounts.listForUser(user.id)).single.providerId, 'github');
      expect(
        await store.accounts.unlinkForUser(user.id, 'github', 'account-1'),
        isTrue,
      );
      expect(await store.accounts.listForUser(user.id), isEmpty);
      expect(
        await store.accounts.unlinkForUser(user.id, 'github', 'account-1'),
        isFalse,
      );

      final now = DateTime.now().toUtc();
      final session = AuthSessionRecord(
        id: 'session-1',
        tokenHash: hashOpaqueToken('session-token-1'),
        userId: user.id,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        lastUsedAt: now,
        authenticationMethod: 'password',
      );
      await store.sessions.create(session);
      expect(await store.sessions.find(session.tokenHash), same(session));
      final replacement = AuthSessionRecord(
        id: 'session-2',
        tokenHash: hashOpaqueToken('session-token-2'),
        userId: user.id,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        lastUsedAt: now,
        authenticationMethod: 'password',
      );
      expect(
        await store.sessions.rotate(
          previousTokenHash: session.tokenHash,
          replacement: replacement,
        ),
        same(replacement),
      );
      expect(
        (await store.sessions.find(session.tokenHash))?.revokedAt,
        isNotNull,
      );
      expect(
        await store.sessions.find(replacement.tokenHash),
        same(replacement),
      );

      final token = AuthVerificationToken(
        identifier: user.email!,
        token: 'verify-me',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await store.verificationTokens.save(token);
      expect(
        await store.verificationTokens.consume(token.identifier, token.token),
        isNotNull,
      );
      expect(
        await store.verificationTokens.consume(token.identifier, token.token),
        isNull,
      );
    });
  });

  test(
    'callback store exposes typed callbacks through typed domains',
    () async {
      final user = AuthUser(id: 'callback-user');
      final emailUser = AuthUser(
        id: 'callback-email-user',
        email: 'email@example.com',
      );
      final hasher = Argon2idPasswordHasher();
      String? updatedPasswordFor;
      DateTime? passwordUpdatedAt;
      String? revokedSessionsFor;
      DateTime? sessionsRevokedAt;
      final credential = AuthPasswordCredential(
        id: 'callback-credential',
        userId: user.id,
        identifier: 'callback-user',
        passwordHash: hasher.hash('test-password'),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final store = CallbackAuthStore(
        onFindUserById: (id) => id == user.id ? user : null,
        onCreateOrFindUserByEmail: (candidate) =>
            AuthUserCreateResult(user: emailUser, created: false),
        onFindCredential: (_) => credential,
        onUpdatePasswordForUser:
            ({
              required String userId,
              required String passwordHash,
              required DateTime updatedAt,
            }) {
              updatedPasswordFor = userId;
              passwordUpdatedAt = updatedAt;
              expect(passwordHash, equals('new-password-hash'));
              return 1;
            },
        onCreateSession: (session) => session,
        onRevokeAllSessionsForUser: (userId, {revokedAt}) {
          revokedSessionsFor = userId;
          sessionsRevokedAt = revokedAt;
          return 2;
        },
      );

      expect(await store.users.findById(user.id), same(user));
      final emailResult = await store.users.createOrFindByEmail(
        AuthUser(id: 'new-email-user', email: 'email@example.com'),
      );
      expect(emailResult.user, same(emailUser));
      expect(emailResult.created, isFalse);
      expect(
        await authorizeCredentialsSignIn(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            username: 'callback-user',
            password: 'test-password',
          ),
        ),
        same(user),
      );
      final now = DateTime.now().toUtc();
      final session = AuthSessionRecord(
        id: 'callback-session',
        tokenHash: hashOpaqueToken('callback-session-token'),
        userId: user.id,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        lastUsedAt: now,
        authenticationMethod: 'password',
      );
      expect(await store.sessions.create(session), same(session));

      final changedAt = now.add(const Duration(minutes: 1));
      expect(
        await store.credentials.updatePasswordForUser(
          userId: user.id,
          passwordHash: 'new-password-hash',
          updatedAt: changedAt,
        ),
        equals(1),
      );
      expect(updatedPasswordFor, equals(user.id));
      expect(passwordUpdatedAt, equals(changedAt));
      expect(
        await store.sessions.revokeAllForUser(user.id, revokedAt: changedAt),
        equals(2),
      );
      expect(revokedSessionsFor, equals(user.id));
      expect(sessionsRevokedAt, equals(changedAt));
    },
  );
}
