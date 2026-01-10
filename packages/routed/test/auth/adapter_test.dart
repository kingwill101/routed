import 'package:routed/auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthAdapter', () {
    test('registers and verifies credentials in memory', () async {
      final adapter = InMemoryAuthAdapter();
      final created = await adapter.registerCredentials(
        AuthCredentials(email: 'user@example.com', password: 'secret'),
      );
      expect(created, isNotNull);

      final verified = await adapter.verifyCredentials(
        AuthCredentials(email: 'user@example.com', password: 'secret'),
      );
      expect(verified?.email, equals('user@example.com'));

      final duplicate = await adapter.registerCredentials(
        AuthCredentials(email: 'user@example.com', password: 'secret'),
      );
      expect(duplicate, isNull);
    });

    test('manages accounts and sessions', () async {
      final adapter = InMemoryAuthAdapter();
      final user = await adapter.createUser(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final account = AuthAccount(
        providerId: 'github',
        providerAccountId: 'acct-1',
        userId: user.id,
      );

      await adapter.linkAccount(account);
      final loaded = await adapter.getAccount('github', 'acct-1');
      expect(loaded?.userId, equals('user-1'));

      final session = AuthSession(user: user, expiresAt: DateTime.now());
      final stored = await adapter.createSession(session);
      expect(stored.user.id, equals('user-1'));

      final fetched = await adapter.getSession(stored.token ?? user.id);
      expect(fetched, isNotNull);

      await adapter.deleteSession(stored.token ?? user.id);
      final removed = await adapter.getSession(stored.token ?? user.id);
      expect(removed, isNull);
    });

    test('rejects invalid credential input', () async {
      final adapter = InMemoryAuthAdapter();
      final missingPassword = await adapter.registerCredentials(
        AuthCredentials(email: 'user@example.com'),
      );
      expect(missingPassword, isNull);

      await adapter.createUser(
        AuthUser(
          id: 'user-1',
          email: 'user@example.com',
          attributes: const {'password': 'secret'},
        ),
      );
      final wrongPassword = await adapter.verifyCredentials(
        AuthCredentials(email: 'user@example.com', password: 'wrong'),
      );
      expect(wrongPassword, isNull);

      final missingIdentifier = await adapter.verifyCredentials(
        AuthCredentials(password: 'secret'),
      );
      expect(missingIdentifier, isNull);

      await adapter.updateUser(
        AuthUser(id: 'user-2', email: 'new@example.com'),
      );
      final noPassword = await adapter.verifyCredentials(
        AuthCredentials(email: 'new@example.com', password: 'secret'),
      );
      expect(noPassword, isNull);
    });

    test('handles verification tokens', () async {
      final adapter = InMemoryAuthAdapter();
      final token = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'abc',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await adapter.saveVerificationToken(token);

      final used = await adapter.useVerificationToken(
        'user@example.com',
        'abc',
      );
      expect(used, isNotNull);

      final usedAgain = await adapter.useVerificationToken(
        'user@example.com',
        'abc',
      );
      expect(usedAgain, isNull);

      final expired = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'expired',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await adapter.saveVerificationToken(expired);
      final expiredResult = await adapter.useVerificationToken(
        'user@example.com',
        'expired',
      );
      expect(expiredResult, isNull);
    });

    test('callback adapter delegates handlers', () async {
      var verified = false;
      var registered = false;
      final adapter = CallbackAuthAdapter(
        onVerifyCredentials: (credentials) {
          verified = true;
          return AuthUser(id: 'verified');
        },
        onRegisterCredentials: (credentials) {
          registered = true;
          return AuthUser(id: 'registered');
        },
      );

      final verifiedUser = await adapter.verifyCredentials(
        AuthCredentials(email: 'user@example.com', password: 'secret'),
      );
      final registeredUser = await adapter.registerCredentials(
        AuthCredentials(email: 'new@example.com', password: 'secret'),
      );

      expect(verified, isTrue);
      expect(registered, isTrue);
      expect(verifiedUser?.id, equals('verified'));
      expect(registeredUser?.id, equals('registered'));
    });

    test('stores and retrieves users by id and email', () async {
      final adapter = InMemoryAuthAdapter();
      await adapter.createUser(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );

      final byId = await adapter.getUserById('user-1');
      final byEmail = await adapter.getUserByEmail('user@example.com');
      expect(byId?.id, equals('user-1'));
      expect(byEmail?.id, equals('user-1'));

      await adapter.updateUser(
        AuthUser(id: 'user-1', email: 'updated@example.com'),
      );
      final updated = await adapter.getUserByEmail('updated@example.com');
      expect(updated, isNotNull);
    });

    test('register rejects missing identifiers', () async {
      final adapter = InMemoryAuthAdapter();
      final missing = await adapter.registerCredentials(
        AuthCredentials(username: '', password: 'secret'),
      );
      expect(missing, isNull);

      await adapter.createUser(AuthUser(id: 'existing'));
      final duplicate = await adapter.registerCredentials(
        AuthCredentials(username: 'existing', password: 'secret'),
      );
      expect(duplicate, isNull);
    });

    test('callback adapter forwards lifecycle hooks', () async {
      var calls = 0;
      final token = AuthVerificationToken(
        identifier: 'user@example.com',
        token: 'verify',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      final adapter = CallbackAuthAdapter(
        onGetUserById: (id) {
          calls += 1;
          return AuthUser(id: id);
        },
        onGetUserByEmail: (email) {
          calls += 1;
          return AuthUser(id: 'email-user', email: email);
        },
        onCreateUser: (user) {
          calls += 1;
          return user;
        },
        onUpdateUser: (user) {
          calls += 1;
          return user;
        },
        onGetAccount: (providerId, providerAccountId) {
          calls += 1;
          return AuthAccount(
            providerId: providerId,
            providerAccountId: providerAccountId,
            userId: 'user-1',
          );
        },
        onLinkAccount: (account) {
          calls += 1;
        },
        onGetSession: (sessionToken) {
          calls += 1;
          return AuthSession(
            user: AuthUser(id: 'user-1'),
            expiresAt: DateTime.now(),
            token: sessionToken,
          );
        },
        onCreateSession: (session) {
          calls += 1;
          return session;
        },
        onDeleteSession: (sessionToken) {
          calls += 1;
        },
        onSaveVerificationToken: (token) {
          calls += 1;
        },
        onUseVerificationToken: (identifier, value) {
          calls += 1;
          return token;
        },
      );

      await adapter.getUserById('user-1');
      await adapter.getUserByEmail('user@example.com');
      await adapter.createUser(AuthUser(id: 'user-1'));
      await adapter.updateUser(AuthUser(id: 'user-1'));
      await adapter.getAccount('github', 'acct');
      await adapter.linkAccount(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'acct',
          userId: 'user-1',
        ),
      );
      await adapter.getSession('token');
      await adapter.createSession(
        AuthSession(
          user: AuthUser(id: 'user-1'),
          expiresAt: DateTime.now(),
        ),
      );
      await adapter.deleteSession('token');
      await adapter.saveVerificationToken(token);
      await adapter.useVerificationToken('user@example.com', 'verify');

      expect(calls, equals(11));
    });
  });

  group('Auth models', () {
    test('AuthUser converts to and from principals', () {
      final user = AuthUser(
        id: 'user-1',
        email: 'user@example.com',
        name: 'User',
        image: 'avatar.png',
        roles: const ['admin'],
        attributes: const {'locale': 'en'},
      );

      final principal = user.toPrincipal();
      expect(principal.id, equals('user-1'));
      expect(principal.roles, contains('admin'));
      expect(principal.attributes['email'], equals('user@example.com'));

      final restored = AuthUser.fromPrincipal(principal);
      expect(restored.email, equals('user@example.com'));
      expect(restored.attributes['locale'], equals('en'));
    });

    test('AuthUser json roundtrip preserves fields', () {
      final user = AuthUser(
        id: 'user-2',
        email: 'mail@example.com',
        roles: const ['viewer'],
        attributes: const {'team': 'alpha'},
      );

      final json = user.toJson();
      final restored = AuthUser.fromJson(json);
      expect(restored.id, equals('user-2'));
      expect(restored.roles, equals(['viewer']));
      expect(restored.attributes['team'], equals('alpha'));
    });

    test('AuthAccount and session serialize', () {
      final account = AuthAccount(
        providerId: 'github',
        providerAccountId: 'acct-1',
        userId: 'user-1',
        accessToken: 'token',
        refreshToken: 'refresh',
        expiresAt: DateTime.parse('2024-01-01T00:00:00Z'),
        metadata: const {'scope': 'read'},
      );

      final session = AuthSession(
        user: AuthUser(id: 'user-1'),
        expiresAt: DateTime.parse('2024-01-01T00:00:00Z'),
        strategy: AuthSessionStrategy.jwt,
        token: 'jwt',
      );

      expect(account.toJson()['provider_id'], equals('github'));
      expect(session.toJson()['strategy'], equals('jwt'));
    });

    test('AuthCredentials fromMap captures attributes', () {
      final credentials = AuthCredentials.fromMap({
        'email': 'user@example.com',
        'password': 'secret',
        'metadata': 'extra',
      });

      expect(credentials.email, equals('user@example.com'));
      expect(credentials.attributes['metadata'], equals('extra'));
    });
  });
}
