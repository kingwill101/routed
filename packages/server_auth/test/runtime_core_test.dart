import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthStore', () {
    test('coordinates all typed domain stores', () async {
      final store = InMemoryAuthStore();

      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      expect(await store.users.findById(user.id), same(user));
      expect(await store.users.findByEmail('user@example.com'), same(user));

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

      final resetToken = buildAuthPasswordResetToken(
        userId: user.id,
        token: 'reset-secret',
        ttl: const Duration(minutes: 10),
      );
      await store.passwordResetTokens.save(resetToken);
      expect(
        (await store.passwordResetTokens.consume('reset-secret'))?.userId,
        equals(user.id),
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
      expect(
        (await store.sessions.find(session.tokenHash))?.userId,
        equals(session.userId),
      );
      final touched = await store.sessions.touch(
        session.tokenHash,
        now.add(const Duration(minutes: 1)),
      );
      expect(touched?.lastUsedAt, equals(now.add(const Duration(minutes: 1))));
      final revoked = await store.sessions.revoke(session.tokenHash);
      expect(revoked?.revokedAt, isNotNull);
      expect(
        await store.sessions.touch(
          session.tokenHash,
          now.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
    });

    test(
      'updates credentials and revokes all active sessions for a user',
      () async {
        final store = InMemoryAuthStore();
        final hasher = Argon2idPasswordHasher();
        final user = await authorizeCredentialsRegistration(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'reset@example.com',
            password: 'old-password-123',
          ),
        );
        expect(user, isNotNull);

        final now = DateTime.now().toUtc();
        AuthSessionRecord session(String id, String userId) =>
            AuthSessionRecord(
              id: id,
              tokenHash: hashOpaqueToken(id),
              userId: userId,
              createdAt: now,
              expiresAt: now.add(const Duration(hours: 1)),
              lastUsedAt: now,
              authenticationMethod: 'password',
            );
        await store.sessions.create(session('reset-session-1', user!.id));
        await store.sessions.create(session('reset-session-2', user.id));
        await store.sessions.create(session('other-session', 'other-user'));

        final changedAt = now.add(const Duration(minutes: 1));
        expect(
          await store.credentials.updatePasswordForUser(
            userId: user.id,
            passwordHash: 'new-password-hash',
            updatedAt: changedAt,
          ),
          equals(1),
        );
        final credential = await store.credentials.findByIdentifier(
          'reset@example.com',
        );
        expect(credential?.passwordHash, equals('new-password-hash'));
        expect(credential?.updatedAt, equals(changedAt));

        expect(
          await store.sessions.revokeAllForUser(user.id, revokedAt: changedAt),
          equals(2),
        );
        expect(
          await store.sessions.touch(
            hashOpaqueToken('reset-session-1'),
            changedAt.add(const Duration(minutes: 1)),
          ),
          isNull,
        );
        expect(
          await store.sessions.touch(
            hashOpaqueToken('reset-session-2'),
            changedAt.add(const Duration(minutes: 1)),
          ),
          isNull,
        );
        expect(
          await store.sessions.touch(
            hashOpaqueToken('other-session'),
            changedAt.add(const Duration(minutes: 1)),
          ),
          isNotNull,
        );
        expect(await store.sessions.revokeAllForUser(user.id), equals(0));
      },
    );

    test('account links preserve the first canonical owner', () async {
      final store = InMemoryAuthStore();
      final first = AuthAccount(
        providerId: 'github',
        providerAccountId: 'account-1',
        userId: 'user-1',
      );
      final competing = AuthAccount(
        providerId: 'github',
        providerAccountId: 'account-1',
        userId: 'user-2',
      );

      final linked = await Future.wait([
        Future.sync(() => store.accounts.link(first)),
        Future.sync(() => store.accounts.link(competing)),
      ]);

      expect(linked, everyElement(same(first)));
      expect(linked.where((account) => account.userId == 'user-2'), isEmpty);
      expect(
        (await store.accounts.find('github', 'account-1'))?.userId,
        equals('user-1'),
      );
    });

    test('account identity keys do not collide on delimiters', () async {
      final store = InMemoryAuthStore();
      await store.accounts.link(
        AuthAccount(
          providerId: 'github::team',
          providerAccountId: 'account-1',
          userId: 'user-1',
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'team::account-1',
          userId: 'user-2',
        ),
      );

      expect(
        (await store.accounts.find('github::team', 'account-1'))?.userId,
        equals('user-1'),
      );
      expect(
        (await store.accounts.find('github', 'team::account-1'))?.userId,
        equals('user-2'),
      );
    });

    test(
      'rejects empty persistence identities at the in-memory boundary',
      () async {
        final store = InMemoryAuthStore();

        await expectLater(
          store.users.create(AuthUser(id: '')),
          throwsArgumentError,
        );
        await expectLater(
          store.accounts.link(
            AuthAccount(
              providerId: '',
              providerAccountId: 'account-1',
              userId: 'user-1',
            ),
          ),
          throwsArgumentError,
        );
        await expectLater(
          store.accounts.link(
            AuthAccount(providerId: 'github', providerAccountId: 'account-1'),
          ),
          throwsArgumentError,
        );
      },
    );

    test('validates session records and uses server time for touch', () async {
      final store = InMemoryAuthStore();
      final now = DateTime.now().toUtc();

      AuthSessionRecord session({
        String id = 'session-1',
        String tokenHash = 'hash-1',
        String userId = 'user-1',
        DateTime? createdAt,
        DateTime? expiresAt,
        DateTime? lastUsedAt,
        String authenticationMethod = 'password',
      }) {
        return AuthSessionRecord(
          id: id,
          tokenHash: tokenHash,
          userId: userId,
          createdAt: createdAt ?? now,
          expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
          lastUsedAt: lastUsedAt ?? now,
          authenticationMethod: authenticationMethod,
        );
      }

      await expectLater(
        store.sessions.create(session(tokenHash: '')),
        throwsArgumentError,
      );
      await expectLater(
        store.sessions.create(session(expiresAt: now, lastUsedAt: now)),
        throwsArgumentError,
      );

      final expiredCreatedAt = now.subtract(const Duration(hours: 2));
      final expired = session(
        id: 'expired',
        tokenHash: 'expired-hash',
        createdAt: expiredCreatedAt,
        expiresAt: now.subtract(const Duration(hours: 1)),
        lastUsedAt: expiredCreatedAt,
      );
      await store.sessions.create(expired);
      expect(
        await store.sessions.touch(
          expired.tokenHash,
          expiredCreatedAt.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
    });

    test(
      'credential registration rejects malformed records and races',
      () async {
        final store = InMemoryAuthStore();
        final now = DateTime.utc(2026, 8, 19);

        Future<AuthUser?> register(String userId, String identifier) async {
          return await store.credentials.register(
            AuthUser(id: userId),
            AuthPasswordCredential(
              id: 'credential-$userId',
              userId: userId,
              identifier: identifier,
              passwordHash: 'encoded-hash',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        final results = await Future.wait([
          register('user-1', 'same-login'),
          register('user-2', 'same-login'),
        ]);
        expect(results.whereType<AuthUser>(), hasLength(1));
        expect(
          await store.credentials.findByIdentifier('same-login'),
          isNotNull,
        );

        expect(
          await store.credentials.register(
            AuthUser(id: 'user-3'),
            AuthPasswordCredential(
              id: '',
              userId: 'user-3',
              identifier: 'other-login',
              passwordHash: 'encoded-hash',
              createdAt: now,
              updatedAt: now,
            ),
          ),
          isNull,
        );
        expect(
          await store.credentials.register(
            AuthUser(id: 'user-4'),
            AuthPasswordCredential(
              id: 'credential-user-4',
              userId: 'user-4',
              identifier: '   ',
              passwordHash: 'encoded-hash',
              createdAt: now,
              updatedAt: now,
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'user persistence preserves email uniqueness and update failures',
      () async {
        final store = InMemoryAuthStore();
        final first = await store.users.create(
          AuthUser(id: 'user-1', email: 'first@example.com'),
        );
        await store.users.create(
          AuthUser(id: 'user-2', email: 'second@example.com'),
        );

        await expectLater(
          store.users.create(
            AuthUser(id: 'user-3', email: 'first@example.com'),
          ),
          throwsStateError,
        );
        expect(
          await store.users.update(
            AuthUser(id: first.id, email: 'second@example.com'),
          ),
          isNull,
        );
        expect(
          (await store.users.findByEmail('first@example.com'))?.id,
          equals(first.id),
        );
        expect(
          (await store.users.findByEmail('second@example.com'))?.id,
          equals('user-2'),
        );
      },
    );

    test(
      'email user creation is atomic and returns the canonical user',
      () async {
        final store = InMemoryAuthStore();
        final results = await Future.wait([
          Future.sync(
            () => store.users.createOrFindByEmail(
              AuthUser(id: 'user-1', email: 'user@example.com'),
            ),
          ),
          Future.sync(
            () => store.users.createOrFindByEmail(
              AuthUser(id: 'user-2', email: 'user@example.com'),
            ),
          ),
        ]);

        expect(results.where((result) => result.created), hasLength(1));
        expect(
          results.map((result) => result.user),
          everyElement(same(results.first.user)),
        );
        expect(
          (await store.users.findByEmail('user@example.com'))?.id,
          equals(results.first.user.id),
        );
      },
    );

    test('coordinates atomic OAuth challenge callbacks', () async {
      AuthOAuthChallenge? saved;
      final store = CallbackAuthStore(
        onSaveOAuthChallenge: (challenge) => saved = challenge,
        onConsumeOAuthChallenge: (providerId, state) {
          if (saved?.providerId == providerId && saved?.state == state) {
            return saved;
          }
          return null;
        },
      );
      final challenge = AuthOAuthChallenge(
        providerId: 'github',
        state: 'state-1',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );

      await store.oauthChallenges.save(challenge);

      expect(saved, same(challenge));
      expect(
        await store.oauthChallenges.consume('github', 'state-1'),
        same(challenge),
      );
      expect(await store.oauthChallenges.consume('google', 'state-1'), isNull);
    });

    test('delegates credential and verification token operations', () async {
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

      final token = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'verify-me',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await store.verificationTokens.save(token);
      expect(
        (await store.verificationTokens.consume(
          token.identifier,
          token.token,
        ))?.token,
        equals(token.token),
      );
    });

    test(
      'rehashes a matching credential when the policy requests it',
      () async {
        final hasher = _RehashingPasswordHasher();
        final store = InMemoryAuthStore();

        await authorizeCredentialsRegistration(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'user@example.com',
            password: 'test-password',
          ),
        );
        expect(hasher.hashCalls, equals(1));

        final verified = await authorizeCredentialsSignIn(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'user@example.com',
            password: 'test-password',
          ),
        );
        expect(verified, isNotNull);
        expect(hasher.hashCalls, equals(2));
      },
    );
  });

  group('AuthRuntime', () {
    test('local options reject production boot explicitly', () {
      final options = AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      );

      expect(options.requireProductionBoot, throwsStateError);
    });

    test('configures plugins in order against one shared store', () {
      final first = _RecordingPlugin('first');
      final second = _RecordingPlugin('second');
      final options = AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: [first],
      );
      final runtime = AuthRuntime<String>(options: options, plugins: [second]);

      expect(runtime.plugins.map((plugin) => plugin.id), ['first', 'second']);
      expect(runtime.plugin(' first '), same(first));
      expect(runtime.hasPlugin('second'), isTrue);
      expect(first.configuredStore, same(runtime.store));
      expect(second.configuredStore, same(runtime.store));
    });

    test('retains typed endpoint contracts and plugin ownership', () {
      final runtime = AuthRuntime<String>(
        options: AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          plugins: <AuthServerPlugin<String>>[AnonymousPlugin<String>()],
        ),
      );
      final endpoint = runtime.registry.endpoints.first;
      final contract = endpoint as AuthEndpointContractDescriptor;

      expect(runtime.registry.pluginIdForEndpoint(endpoint.id), 'anonymous');
      expect(contract.requestCodec.schema, <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
      });
      expect(contract.requestCodec.contentType, 'application/json');
      expect(contract.requestCodec.required, isFalse);

      final codec = AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => value,
        encode: (value) => value,
        schema: const <String, Object?>{'type': 'object'},
        contentType: 'application/x-www-form-urlencoded',
        required: true,
      );
      expect(codec.schema, const <String, Object?>{'type': 'object'});
      expect(codec.contentType, 'application/x-www-form-urlencoded');
      expect(codec.required, isTrue);
    });

    test('rejects empty and duplicate plugin IDs', () {
      expect(
        () => AuthRuntime<String>(
          options: AuthOptions<String>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: [_RecordingPlugin('')],
          ),
        ),
        throwsArgumentError,
      );

      final duplicate = _RecordingPlugin('duplicate');
      expect(
        () => AuthRuntime<String>(
          options: AuthOptions<String>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: [duplicate],
          ),
          plugins: [_RecordingPlugin('duplicate')],
        ),
        throwsStateError,
      );
    });
  });
}

class _RecordingPlugin implements AuthServerPlugin<String> {
  _RecordingPlugin(this.id);

  @override
  final String id;

  AuthStore? configuredStore;

  @override
  void configure(AuthServerPluginContext<String> context) {
    configuredStore = context.store;
  }
}

class _RehashingPasswordHasher implements PasswordHasher {
  int hashCalls = 0;

  @override
  String hash(String password) {
    hashCalls++;
    return 'test-hash';
  }

  @override
  PasswordVerification verify(String password, String encodedHash) {
    return PasswordVerification(
      matches: encodedHash == 'test-hash' && password == 'test-password',
      needsRehash: true,
    );
  }
}
