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
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
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
      ]);
      expect(
        plugin.endpoints,
        everyElement(isA<AuthEndpointContractDescriptor>()),
      );
      expect(plugin.clientOperations.map((operation) => operation.path), [
        '/username/register',
        '/username/sign-in',
      ]);
      expect(
        plugin.rateLimitOperations,
        containsAll([
          authUsernameRegistrationRateLimitOperation,
          authUsernameSignInRateLimitOperation,
        ]),
      );
    });
  });
}
