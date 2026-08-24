import 'dart:async';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

final class _CaptchaVerifier implements AuthCaptchaVerifier<String> {
  _CaptchaVerifier(this.response);

  final FutureOr<AuthCaptchaVerificationResult> Function(
    AuthCaptchaVerificationRequest<String> request,
  )
  response;
  final List<AuthCaptchaVerificationRequest<String>> requests =
      <AuthCaptchaVerificationRequest<String>>[];

  @override
  FutureOr<AuthCaptchaVerificationResult> verify(
    AuthCaptchaVerificationRequest<String> request,
  ) {
    requests.add(request);
    return response(request);
  }
}

final class _BreachedLookup implements AuthBreachedPasswordLookup<String> {
  _BreachedLookup(this.response);

  final FutureOr<AuthBreachedPasswordCheckResult> Function(
    AuthBreachedPasswordCheckRequest<String> request,
  )
  response;
  final List<AuthBreachedPasswordCheckRequest<String>> requests =
      <AuthBreachedPasswordCheckRequest<String>>[];

  @override
  FutureOr<AuthBreachedPasswordCheckResult> check(
    AuthBreachedPasswordCheckRequest<String> request,
  ) {
    requests.add(request);
    return response(request);
  }
}

AuthCredentialPolicyRequest<String> _credentialRequest({
  String? token,
  AuthCredentialPolicyOperation operation =
      AuthCredentialPolicyOperation.signIn,
}) => AuthCredentialPolicyRequest<String>(
  context: 'request-context',
  provider: CredentialsProvider(),
  operation: operation,
  identifier: 'user@example.com',
  verificationToken: token,
);

AuthPasswordPolicyRequest<String> _passwordRequest({
  String password = 'safe-password-123',
  AuthPasswordPolicyOperation operation =
      AuthPasswordPolicyOperation.registration,
}) => AuthPasswordPolicyRequest<String>(
  context: 'request-context',
  operation: operation,
  password: password,
  user: AuthUser(id: 'user-1', email: 'user@example.com'),
);

AuthRuntime<String> _runtimeWith(AuthServerPlugin<String> plugin) =>
    AuthRuntime<String>(
      options: AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<String>>[plugin],
      ),
    );

void main() {
  group('CaptchaPlugin', () {
    test('verifies only at credential policy boundaries', () async {
      final verifier = _CaptchaVerifier(
        (_) => const AuthCaptchaVerificationResult.accepted(),
      );
      final plugin = CaptchaPlugin<String>(verifier: verifier);
      final runtime = _runtimeWith(plugin);

      await runtime.registry.enforceCredentialPolicy(
        _credentialRequest(token: 'captcha-token'),
      );

      expect(verifier.requests, hasLength(1));
      expect(verifier.requests.single.token, 'captcha-token');
      expect(
        verifier.requests.single.operation,
        AuthCredentialPolicyOperation.signIn,
      );
      expect(runtime.hasPlugin(authCaptchaPluginId), isTrue);
    });

    test('passes an opaque captcha token to the provider unchanged', () async {
      final verifier = _CaptchaVerifier(
        (_) => const AuthCaptchaVerificationResult.accepted(),
      );
      final runtime = _runtimeWith(CaptchaPlugin<String>(verifier: verifier));

      await runtime.registry.enforceCredentialPolicy(
        _credentialRequest(token: ' opaque-captcha-token '),
      );

      expect(verifier.requests.single.token, ' opaque-captcha-token ');
    });

    test(
      'rejects malformed and oversized tokens without calling the provider',
      () async {
        var calls = 0;
        final plugin = CaptchaPlugin<String>(
          verifier: _CaptchaVerifier((_) {
            calls += 1;
            return const AuthCaptchaVerificationResult.accepted();
          }),
          config: const AuthCaptchaPluginConfig(maxTokenLength: 8),
        );
        final runtime = _runtimeWith(plugin);

        for (final token in <String?>[null, '', '       ', '123456789']) {
          await expectLater(
            runtime.registry.enforceCredentialPolicy(
              _credentialRequest(token: token),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                authCaptchaFailedErrorCode,
              ),
            ),
          );
        }
        expect(calls, 0);
      },
    );

    test(
      'collapses provider exceptions and timeouts to a generic error',
      () async {
        const secretToken = 'captcha-vendor-token';
        final exceptionPlugin = CaptchaPlugin<String>(
          verifier: _CaptchaVerifier((_) {
            throw StateError('vendor leaked $secretToken');
          }),
        );
        final exceptionRuntime = _runtimeWith(exceptionPlugin);
        final exception = await catchError(
          exceptionRuntime.registry.enforceCredentialPolicy(
            _credentialRequest(token: secretToken),
          ),
        );
        expect(exception.code, authCaptchaFailedErrorCode);
        expect(exception.toString(), isNot(contains(secretToken)));

        final timeoutPlugin = CaptchaPlugin<String>(
          verifier: _CaptchaVerifier(
            (_) => Future<AuthCaptchaVerificationResult>.delayed(
              const Duration(milliseconds: 30),
              () => const AuthCaptchaVerificationResult.accepted(),
            ),
          ),
          config: const AuthCaptchaPluginConfig(
            providerTimeout: Duration(milliseconds: 1),
          ),
        );
        await expectLater(
          _runtimeWith(timeoutPlugin).registry.enforceCredentialPolicy(
            _credentialRequest(token: 'timeout-token'),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              authCaptchaFailedErrorCode,
            ),
          ),
        );
      },
    );

    test('one-time mode rejects sequential and concurrent replays', () async {
      var now = DateTime.utc(2030);
      final verifier = _CaptchaVerifier((_) async {
        await Future<void>.delayed(Duration.zero);
        return const AuthCaptchaVerificationResult.accepted();
      });
      final plugin = CaptchaPlugin<String>(
        verifier: verifier,
        config: AuthCaptchaPluginConfig(
          tokenUsePolicy: AuthCaptchaTokenUsePolicy.oneTime,
          clock: () => now,
        ),
      );
      final runtime = _runtimeWith(plugin);

      await runtime.registry.enforceCredentialPolicy(
        _credentialRequest(token: 'one-time-token'),
      );
      await expectLater(
        runtime.registry.enforceCredentialPolicy(
          _credentialRequest(token: 'one-time-token'),
        ),
        throwsA(isA<AuthFlowException>()),
      );
      expect(verifier.requests, hasLength(1));

      final concurrent = await Future.wait(<Future<bool>>[
        runtime.registry
            .enforceCredentialPolicy(
              _credentialRequest(token: 'concurrent-token'),
            )
            .then((_) => true)
            .catchError((_) => false),
        runtime.registry
            .enforceCredentialPolicy(
              _credentialRequest(token: 'concurrent-token'),
            )
            .then((_) => true)
            .catchError((_) => false),
      ]);
      expect(concurrent, containsAll(<bool>[true, false]));

      now = now.add(const Duration(minutes: 11));
      await runtime.registry.enforceCredentialPolicy(
        _credentialRequest(token: 'one-time-token'),
      );
      expect(verifier.requests, hasLength(3));
    });

    test(
      'one-time retention begins after delayed provider acceptance',
      () async {
        var now = DateTime.utc(2030);
        final verifier = _CaptchaVerifier((_) async {
          now = now.add(const Duration(milliseconds: 20));
          await Future<void>.delayed(Duration.zero);
          return const AuthCaptchaVerificationResult.accepted();
        });
        final runtime = _runtimeWith(
          CaptchaPlugin<String>(
            verifier: verifier,
            config: AuthCaptchaPluginConfig(
              tokenUsePolicy: AuthCaptchaTokenUsePolicy.oneTime,
              replayRetention: const Duration(milliseconds: 1),
              clock: () => now,
            ),
          ),
        );

        await runtime.registry.enforceCredentialPolicy(
          _credentialRequest(token: 'delayed-provider-token'),
        );

        await expectLater(
          runtime.registry.enforceCredentialPolicy(
            _credentialRequest(token: 'delayed-provider-token'),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              authCaptchaFailedErrorCode,
            ),
          ),
        );
        expect(verifier.requests, hasLength(1));
      },
    );
  });

  group('BreachedPasswordPlugin', () {
    test('checks enabled password mutation operations', () async {
      final lookup = _BreachedLookup(
        (_) => const AuthBreachedPasswordCheckResult.allowed(),
      );
      final plugin = BreachedPasswordPlugin<String>(lookup: lookup);
      final runtime = _runtimeWith(plugin);

      for (final operation in AuthPasswordPolicyOperation.values) {
        await runtime.registry.enforcePasswordPolicy(
          _passwordRequest(operation: operation),
        );
      }

      expect(
        lookup.requests.map((request) => request.operation),
        AuthPasswordPolicyOperation.values,
      );
    });

    test('rejects a breached password without exposing it', () async {
      const password = 'known-breached-password';
      final lookup = _BreachedLookup(
        (_) => const AuthBreachedPasswordCheckResult.breached(),
      );
      final runtime = _runtimeWith(
        BreachedPasswordPlugin<String>(lookup: lookup),
      );

      final error = await catchError(
        runtime.registry.enforcePasswordPolicy(
          _passwordRequest(password: password),
        ),
      );
      expect(error.code, authBreachedPasswordRejectedErrorCode);
      expect(error.toString(), isNot(contains(password)));
      expect(lookup.requests.single.password, password);
    });

    test(
      'fails closed on lookup exceptions, timeouts, and oversized input',
      () async {
        const password = 'safe-password-123';
        final exceptionPlugin = BreachedPasswordPlugin<String>(
          lookup: _BreachedLookup((_) {
            throw StateError('lookup leaked $password');
          }),
        );
        final exception = await catchError(
          _runtimeWith(exceptionPlugin).registry.enforcePasswordPolicy(
            _passwordRequest(),
          ),
        );
        expect(exception.code, authBreachedPasswordRejectedErrorCode);
        expect(exception.toString(), isNot(contains(password)));

        final timeoutPlugin = BreachedPasswordPlugin<String>(
          lookup: _BreachedLookup(
            (_) => Future<AuthBreachedPasswordCheckResult>.delayed(
              const Duration(milliseconds: 30),
              () => const AuthBreachedPasswordCheckResult.allowed(),
            ),
          ),
          config: const AuthBreachedPasswordPluginConfig(
            providerTimeout: Duration(milliseconds: 1),
          ),
        );
        await expectLater(
          _runtimeWith(
            timeoutPlugin,
          ).registry.enforcePasswordPolicy(_passwordRequest()),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              authBreachedPasswordRejectedErrorCode,
            ),
          ),
        );

        final oversized = BreachedPasswordPlugin<String>(
          lookup: _BreachedLookup(
            (_) => const AuthBreachedPasswordCheckResult.allowed(),
          ),
          config: const AuthBreachedPasswordPluginConfig(maxPasswordLength: 12),
        );
        await expectLater(
          _runtimeWith(oversized).registry.enforcePasswordPolicy(
            _passwordRequest(),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              authBreachedPasswordRejectedErrorCode,
            ),
          ),
        );
      },
    );

    test('preserves built-in password validation before lookup', () async {
      var calls = 0;
      final plugin = BreachedPasswordPlugin<String>(
        lookup: _BreachedLookup((_) {
          calls += 1;
          return const AuthBreachedPasswordCheckResult.allowed();
        }),
      );

      await expectLater(
        _runtimeWith(
          plugin,
        ).registry.enforcePasswordPolicy(_passwordRequest(password: 'short')),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'password_too_short',
          ),
        ),
      );
      expect(calls, 0);
    });
  });
}

Future<AuthFlowException> catchError(Future<void> future) async {
  try {
    await future;
  } on AuthFlowException catch (error) {
    return error;
  }
  fail('Expected AuthFlowException');
}
