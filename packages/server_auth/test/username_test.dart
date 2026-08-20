import 'dart:async';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

final class _Hasher implements PasswordHasher {
  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'hash:$password',
        needsRehash: false,
      );
}

final class _SessionControl implements AuthServerPluginSessionControl {
  @override
  String? get currentSessionId => null;

  @override
  AuthSessionStrategy get strategy => AuthSessionStrategy.session;

  @override
  Future<void> signOut() async {}
}

final class _CaptchaVerifier implements AuthCaptchaVerifier<String> {
  final List<AuthCaptchaVerificationRequest<String>> requests = [];

  @override
  AuthCaptchaVerificationResult verify(
    AuthCaptchaVerificationRequest<String> request,
  ) {
    requests.add(request);
    return const AuthCaptchaVerificationResult.accepted();
  }
}

final class _BreachedLookup implements AuthBreachedPasswordLookup<String> {
  final List<String> passwords = [];

  @override
  AuthBreachedPasswordCheckResult check(
    AuthBreachedPasswordCheckRequest<String> request,
  ) {
    passwords.add(request.password);
    return const AuthBreachedPasswordCheckResult.allowed();
  }
}

UsernamePlugin<String> _plugin({
  InMemoryAuthStore? store,
  Iterable<AuthServerPlugin<String>> protections = const [],
}) {
  final plugin = UsernamePlugin<String>();
  AuthRuntime<String>(
    options: AuthOptions<String>(
      providers: const <AuthProvider>[],
      store: store ?? InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      passwordHasher: _Hasher(),
      plugins: <AuthServerPlugin<String>>[plugin, ...protections],
    ),
  );
  return plugin;
}

Future<Object> _capture(Future<Object> Function() action) async {
  try {
    return await action();
  } catch (error) {
    return error;
  }
}

void main() {
  group('AuthUsernameIdentifierPolicy', () {
    test('canonicalizes configured usernames and resolves email intent', () {
      final policy = AuthUsernameIdentifierPolicy();
      expect(policy.normalizeUsername('  Alice.Example  '), 'alice.example');
      expect(
        policy.resolve('ALICE@example.COM')?.kind,
        AuthUsernameIdentifierKind.email,
      );
      expect(policy.resolve('ALICE@example.COM')?.value, 'alice@example.com');
      expect(policy.resolve('not-an-email@'), isNull);
      expect(policy.normalizeUsername('not-an-email@'), isNull);
    });

    test('supports explicit case, length, and character policy', () {
      final policy = AuthUsernameIdentifierPolicy(
        caseCanonicalization: AuthUsernameCaseCanonicalization.preserve,
        minimumLength: 2,
        maximumLength: 8,
        allowedCharactersPattern: r'[A-Za-z0-9]',
      );
      expect(policy.normalizeUsername('Ada7'), 'Ada7');
      expect(policy.normalizeUsername('ada-seven'), isNull);
      expect(policy.normalizeUsername('a'), isNull);
      expect(policy.normalizeUsername('123456789'), isNull);
    });
  });

  group('UsernamePlugin', () {
    test('requires an explicitly capable atomic store', () {
      final store = CallbackAuthStore();
      final registry = AuthServerPluginRegistry<String>(
        store: store,
        authenticationMethods: AuthAuthenticationMethodService(store: store),
        passwordHasher: _Hasher(),
      );
      expect(
        () => registry.register(UsernamePlugin<String>()),
        throwsA(isA<StateError>()),
      );
    });

    test('registers once and signs in by username or email', () async {
      final plugin = _plugin();
      final registered = await plugin.register(
        context: 'register',
        request: const AuthUsernameRegistrationRequest(
          username: ' Alice ',
          email: 'ALICE@EXAMPLE.COM',
          password: 'safe-password-123',
        ),
        sessionControl: _SessionControl(),
      );

      expect(registered.username, 'alice');
      expect(registered.user.email, 'alice@example.com');
      expect(registered.user.attributes['username'], 'alice');

      for (final identifier in ['ALICE', 'alice@example.com']) {
        final signedIn = await plugin.signIn(
          context: 'sign-in',
          request: AuthUsernameSignInRequest(
            identifier: identifier,
            password: 'safe-password-123',
          ),
          sessionControl: _SessionControl(),
        );
        expect(signedIn.user.id, registered.user.id);
        expect(signedIn.username, 'alice');
      }
    });

    test(
      'returns one generic error for malformed and unknown sign-in',
      () async {
        final plugin = _plugin();
        for (final identifier in ['bad@', 'unknown-user']) {
          await expectLater(
            plugin.signIn(
              context: 'sign-in',
              request: AuthUsernameSignInRequest(
                identifier: identifier,
                password: 'safe-password-123',
              ),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'invalid_credentials',
              ),
            ),
          );
        }
      },
    );

    test(
      'shares email uniqueness with ordinary credential registration',
      () async {
        final store = InMemoryAuthStore();
        final existing = await authorizeCredentialsRegistration(
          store: store,
          passwordHasher: _Hasher(),
          provider: CredentialsProvider(),
          context: 'legacy-registration',
          credentials: AuthCredentials(
            email: 'claimed@example.com',
            password: 'safe-password-123',
          ),
        );
        expect(existing, isNotNull);
        final plugin = _plugin(store: store);

        await expectLater(
          plugin.register(
            context: 'username-registration',
            request: const AuthUsernameRegistrationRequest(
              username: 'different-user',
              email: 'CLAIMED@EXAMPLE.COM',
              password: 'safe-password-123',
            ),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'registration_failed',
            ),
          ),
        );
        expect(
          await store.users.findByEmail('claimed@example.com'),
          same(existing),
        );
      },
    );

    test('same canonical username has exactly one concurrent winner', () async {
      final plugin = _plugin();
      final outcomes = await Future.wait(
        List.generate(
          32,
          (index) => _capture(
            () => plugin.register(
              context: 'registration-$index',
              request: AuthUsernameRegistrationRequest(
                username: index.isEven ? 'RaceUser' : ' raceuser ',
                email: 'race-$index@example.com',
                password: 'safe-password-123',
              ),
            ),
          ),
        ),
      );
      expect(
        outcomes.whereType<AuthUsernameAuthenticationResult>(),
        hasLength(1),
      );
      expect(
        outcomes.whereType<AuthFlowException>().map((error) => error.code),
        everyElement('registration_failed'),
      );
    });

    test('same normalized email has exactly one concurrent winner', () async {
      final plugin = _plugin();
      final outcomes = await Future.wait(
        List.generate(
          32,
          (index) => _capture(
            () => plugin.register(
              context: 'registration-$index',
              request: AuthUsernameRegistrationRequest(
                username: 'user$index',
                email: index.isEven
                    ? 'SHARED@EXAMPLE.COM'
                    : ' shared@example.com ',
                password: 'safe-password-123',
              ),
            ),
          ),
        ),
      );
      expect(
        outcomes.whereType<AuthUsernameAuthenticationResult>(),
        hasLength(1),
      );
      expect(
        outcomes.whereType<AuthFlowException>().map((error) => error.code),
        everyElement('registration_failed'),
      );
    });

    test(
      'rename collision preserves the old reservation and projection',
      () async {
        final store = InMemoryAuthStore();
        final plugin = _plugin(store: store);
        final first = await plugin.register(
          context: 'first',
          request: const AuthUsernameRegistrationRequest(
            username: 'first-user',
            password: 'safe-password-123',
          ),
        );
        await plugin.register(
          context: 'second',
          request: const AuthUsernameRegistrationRequest(
            username: 'second-user',
            password: 'safe-password-123',
          ),
        );

        await expectLater(
          plugin.changeUsername(
            userId: first.user.id,
            request: const AuthUsernameChangeRequest(username: ' SECOND-USER '),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'username_change_failed',
            ),
          ),
        );

        expect(
          (await store.findByUsername('first-user'))?.userId,
          first.user.id,
        );
        expect(await store.users.findById(first.user.id), same(first.user));
        expect(await store.findByUsername('second-user'), isNotNull);
      },
    );

    test(
      'concurrent renames have one winner and never lose the old name early',
      () async {
        final store = InMemoryAuthStore();
        final plugin = _plugin(store: store);
        final registered = await plugin.register(
          context: 'register',
          request: const AuthUsernameRegistrationRequest(
            username: 'rename-race',
            password: 'safe-password-123',
          ),
        );

        final outcomes = await Future.wait([
          _capture(
            () => plugin.changeUsername(
              userId: registered.user.id,
              request: const AuthUsernameChangeRequest(username: 'winner-one'),
            ),
          ),
          _capture(
            () => plugin.changeUsername(
              userId: registered.user.id,
              request: const AuthUsernameChangeRequest(username: 'winner-two'),
            ),
          ),
        ]);

        expect(outcomes.whereType<AuthUsernameChangeResult>(), hasLength(1));
        expect(
          outcomes.whereType<AuthFlowException>().single.code,
          'username_change_failed',
        );
        expect(await store.findByUsername('rename-race'), isNull);
        final current = await store.findUsernameForUser(registered.user.id);
        expect(current?.identifier, anyOf('winner-one', 'winner-two'));
        expect(
          (await store.users.findById(
            registered.user.id,
          ))?.attributes['username'],
          current?.identifier,
        );
      },
    );

    test('same-target rename replay is deterministic and idempotent', () async {
      final plugin = _plugin();
      final registered = await plugin.register(
        context: 'register',
        request: const AuthUsernameRegistrationRequest(
          username: 'before-replay',
          password: 'safe-password-123',
        ),
      );

      final first = await plugin.changeUsername(
        userId: registered.user.id,
        request: const AuthUsernameChangeRequest(username: 'after-replay'),
      );
      final replay = await plugin.changeUsername(
        userId: registered.user.id,
        request: const AuthUsernameChangeRequest(username: ' AFTER-REPLAY '),
      );

      expect(first.changed, isTrue);
      expect(replay.changed, isFalse);
      expect(replay.username, first.username);
      expect(replay.user.id, first.user.id);
    });

    test(
      'registration and rename faults roll back every owned record',
      () async {
        AuthUsernameFaultPoint? armed =
            AuthUsernameFaultPoint.registrationAfterUserWrite;
        final store = InMemoryAuthStore(
          usernameFaultInjector: (point) {
            if (point == armed) {
              armed = null;
              throw StateError('injected username fault');
            }
          },
        );
        final plugin = _plugin(store: store);

        await expectLater(
          plugin.register(
            context: 'faulted-register',
            request: const AuthUsernameRegistrationRequest(
              username: 'fault-register',
              email: 'fault-register@example.com',
              password: 'safe-password-123',
            ),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'registration_failed',
            ),
          ),
        );
        expect(await store.findByUsername('fault-register'), isNull);
        expect(
          await store.users.findByEmail('fault-register@example.com'),
          isNull,
        );

        final registered = await plugin.register(
          context: 'successful-register',
          request: const AuthUsernameRegistrationRequest(
            username: 'fault-before',
            password: 'safe-password-123',
          ),
        );
        armed = AuthUsernameFaultPoint.changeAfterCredentialWrite;
        await expectLater(
          plugin.changeUsername(
            userId: registered.user.id,
            request: const AuthUsernameChangeRequest(username: 'fault-after'),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'username_change_failed',
            ),
          ),
        );
        expect(await store.findByUsername('fault-after'), isNull);
        expect(
          (await store.findUsernameForUser(registered.user.id))?.identifier,
          'fault-before',
        );
        expect(
          (await store.users.findById(
            registered.user.id,
          ))?.attributes['username'],
          'fault-before',
        );
      },
    );

    test(
      'disabled and locked users fail every username path generically',
      () async {
        final store = InMemoryAuthStore();
        final plugin = _plugin(store: store);
        final disabled = await plugin.register(
          context: 'disabled-register',
          request: const AuthUsernameRegistrationRequest(
            username: 'disabled-name',
            password: 'safe-password-123',
          ),
        );
        await store.disable(disabled.user.id);
        final locked = await plugin.register(
          context: 'locked-register',
          request: const AuthUsernameRegistrationRequest(
            username: 'locked-name',
            password: 'safe-password-123',
          ),
        );
        await store.upsert(
          AuthAccountState(
            userId: locked.user.id,
            lockedUntil: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );

        for (final (user, target) in [
          (disabled.user, 'disabled-new'),
          (locked.user, 'locked-new'),
        ]) {
          await expectLater(
            plugin.changeUsername(
              userId: user.id,
              request: AuthUsernameChangeRequest(username: target),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'username_change_failed',
              ),
            ),
          );
          expect(await store.findByUsername(target), isNull);
          await expectLater(
            plugin.signIn(
              context: 'unavailable-sign-in',
              request: AuthUsernameSignInRequest(
                identifier: user.attributes['username']! as String,
                password: 'safe-password-123',
              ),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'invalid_credentials',
              ),
            ),
          );
          await expectLater(
            plugin.removeUsername(userId: user.id),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'username_removal_failed',
              ),
            ),
          );
        }
        expect(
          (await plugin.authenticationMethodsForUser(disabled.user.id)).methods,
          isEmpty,
        );
        expect(
          (await plugin.authenticationMethodsForUser(locked.user.id)).methods,
          isEmpty,
        );
      },
    );

    test(
      'safe removal updates inventory, projection, replay, and hard deletion',
      () async {
        final store = InMemoryAuthStore();
        final plugin = UsernamePlugin<String>();
        AuthRuntime<String>(
          options: AuthOptions<String>(
            providers: const <AuthProvider>[
              AuthProvider(
                id: 'github',
                name: 'GitHub',
                type: AuthProviderType.oauth,
              ),
            ],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            passwordHasher: _Hasher(),
            plugins: <AuthServerPlugin<String>>[plugin],
          ),
        );
        final registered = await plugin.register(
          context: 'register',
          request: const AuthUsernameRegistrationRequest(
            username: 'remove-name',
            password: 'safe-password-123',
          ),
        );
        await store.accounts.link(
          AuthAccount(
            providerId: 'github',
            providerAccountId: 'github-account',
            userId: registered.user.id,
          ),
        );

        await plugin.removeUsername(userId: registered.user.id);
        await plugin.removeUsername(userId: registered.user.id);
        expect(await store.findByUsername('remove-name'), isNull);
        expect(
          (await store.users.findById(registered.user.id))?.attributes,
          isNot(contains('username')),
        );

        final replacement = await plugin.register(
          context: 'replacement',
          request: const AuthUsernameRegistrationRequest(
            username: 'hard-delete-name',
            password: 'safe-password-123',
          ),
        );
        expect(
          await store.deleteUserForAdministration(replacement.user.id),
          isTrue,
        );
        expect(await store.findByUsername('hard-delete-name'), isNull);
        final reused = await plugin.register(
          context: 'reuse',
          request: const AuthUsernameRegistrationRequest(
            username: 'hard-delete-name',
            password: 'safe-password-123',
          ),
        );
        expect(reused.user.id, isNot(replacement.user.id));
      },
    );

    test('runs captcha before breached-password registration policy', () async {
      final captcha = _CaptchaVerifier();
      final breached = _BreachedLookup();
      final plugin = _plugin(
        protections: [
          CaptchaPlugin<String>(verifier: captcha),
          BreachedPasswordPlugin<String>(lookup: breached),
        ],
      );

      await plugin.register(
        context: 'protected',
        request: const AuthUsernameRegistrationRequest(
          username: 'protected-user',
          password: 'safe-password-123',
          captchaToken: 'opaque-captcha-token',
        ),
      );

      expect(captcha.requests.single.identifier, 'protected-user');
      expect(captcha.requests.single.token, 'opaque-captcha-token');
      expect(breached.passwords, ['safe-password-123']);
    });

    test('issues a pending challenge when two-factor is enabled', () async {
      var sequence = 0;
      final twoFactor = TwoFactorPlugin<String>(
        backend: InMemoryAuthTwoFactorBackend(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: (length) {
          final current = sequence++;
          return List<int>.generate(
            length,
            (index) => (current * 31 + index + 1) & 0xff,
          );
        },
      );
      final plugin = _plugin(protections: [twoFactor]);
      final registered = await plugin.register(
        context: 'registration',
        request: const AuthUsernameRegistrationRequest(
          username: 'two-factor-user',
          password: 'safe-password-123',
        ),
      );
      final now = DateTime.now().toUtc();
      final enrollment = await twoFactor.beginEnrollment(
        registered.user.id,
        now: now,
      );
      final code = generateAuthTotpCode(
        enrollment.secret,
        timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
      );
      await twoFactor.verifyEnrollment(registered.user.id, code, now: now);

      await expectLater(
        plugin.signIn(
          context: 'sign-in',
          request: const AuthUsernameSignInRequest(
            identifier: 'two-factor-user',
            password: 'safe-password-123',
          ),
          sessionControl: _SessionControl(),
        ),
        throwsA(isA<AuthTwoFactorRequiredException>()),
      );
    });

    test('exposes typed endpoint and client operation contracts', () {
      final plugin = _plugin();
      expect(plugin.endpoints.map((endpoint) => endpoint.id), [
        'username.register',
        'username.signIn',
        'username.change',
        'username.remove',
      ]);
      expect(
        plugin.endpoints,
        everyElement(isA<AuthEndpointContractDescriptor>()),
      );
      expect(plugin.clientOperations.map((operation) => operation.path), [
        '/username/register',
        '/username/sign-in',
        '/username/change',
        '/username/remove',
      ]);
      expect(
        plugin.rateLimitOperations,
        containsAll([
          authUsernameRegistrationRateLimitOperation,
          authUsernameSignInRateLimitOperation,
          authUsernameChangeRateLimitOperation,
          authUsernameRemovalRateLimitOperation,
        ]),
      );
      final durable = plugin.endpoints
          .where((endpoint) => endpoint.id != 'username.signIn')
          .map((endpoint) => endpoint.semantics)
          .whereType<AuthMutationOperationSemantics>();
      expect(
        durable.map((semantics) => semantics.persistence.atomicity),
        everyElement(AuthMutationAtomicity.atomic),
      );
    });
  });
}
