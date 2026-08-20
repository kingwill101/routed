import 'dart:convert';

import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

const _signingKey = 'last-authentication-method-test-signing-key-32-bytes';

final class _CookieStore
    implements AuthLastAuthenticationMethodBrowserStore<String> {
  AuthLastAuthenticationMethodCookie? last;

  @override
  String? readCookie(String context, String name) {
    if (last?.name != name) return null;
    return last!.value;
  }

  @override
  void writeCookie(String context, AuthLastAuthenticationMethodCookie cookie) {
    last = cookie;
  }
}

final class _ThrowingCookieStore
    implements AuthLastAuthenticationMethodBrowserStore<String> {
  @override
  String? readCookie(String context, String name) => 'malformed';

  @override
  void writeCookie(String context, AuthLastAuthenticationMethodCookie cookie) {
    throw StateError('browser adapter unavailable');
  }
}

void main() {
  group('AuthLastAuthenticationMethodPolicy', () {
    test('requires bounded explicit policy values', () {
      expect(
        () => AuthLastAuthenticationMethodId.parse('credentials|token'),
        throwsFormatException,
      );
      expect(
        () => AuthLastAuthenticationMethodId.parse('a' * 65),
        throwsFormatException,
      );
      expect(
        () => AuthLastAuthenticationMethodId.parse(' credentials'),
        throwsFormatException,
      );
      expect(
        () => AuthLastAuthenticationMethodId.oauthProvider('Google/attacker'),
        throwsFormatException,
      );
      expect(
        () => AuthLastAuthenticationMethodPolicy(allowedMethods: const []),
        throwsArgumentError,
      );
      expect(
        () => AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
          retention: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
          maximumStateBytes: 4096,
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
          cookiePath: '/auth\r\nX-Injected: yes',
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
          cookiePath: '/auth',
        ),
        throwsArgumentError,
      );
    });

    test('cookie security flags cannot be relaxed', () {
      final policy = AuthLastAuthenticationMethodPolicy(
        allowedMethods: {AuthLastAuthenticationMethodId.credentials},
      );
      expect(policy.secureCookie, isTrue);
      expect(policy.httpOnlyCookie, isTrue);
      expect(
        () => AuthLastAuthenticationMethodCookie(
          name: policy.cookieName,
          value: 'state',
          path: policy.cookiePath,
          sameSite: policy.sameSite,
          secure: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AuthLastAuthenticationMethodPlugin', () {
    late _CookieStore store;
    late DateTime now;
    late AuthLastAuthenticationMethodPlugin<String> plugin;

    setUp(() {
      store = _CookieStore();
      now = DateTime.utc(2026, 8, 20, 12);
      plugin = AuthLastAuthenticationMethodPlugin<String>(
        signingKey: _signingKey,
        browserStore: store,
        policy: AuthLastAuthenticationMethodPolicy(
          allowedMethods: <AuthLastAuthenticationMethodId>{
            AuthLastAuthenticationMethodId.credentials,
            AuthLastAuthenticationMethodId.usernamePassword,
            AuthLastAuthenticationMethodId.phone,
            AuthLastAuthenticationMethodId.emailOtp,
            AuthLastAuthenticationMethodId.anonymous,
            AuthLastAuthenticationMethodId.passkey,
            AuthLastAuthenticationMethodId.oauthProvider('google'),
          },
          retention: const Duration(minutes: 5),
          maximumStateBytes: 512,
        ),
        clock: () => now,
      );
    });

    test(
      'updates only through the registered successful lifecycle event',
      () async {
        final runtime = AuthRuntime<String>(
          options: AuthOptions<String>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: <AuthServerPlugin<String>>[plugin],
          ),
        );

        expect(store.last, isNull);
        await runtime.registry.emitAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.session,
            authenticationMethod: 'credentials',
          ),
        );

        expect(store.last, isNotNull);
        expect(store.last!.secure, isTrue);
        expect(store.last!.httpOnly, isTrue);
        expect(store.last!.sameSite, AuthLastAuthenticationMethodSameSite.lax);
        expect(store.last!.maxAge, 300);
        final result = await plugin.read('browser');
        expect(result?.method, AuthLastAuthenticationMethodId.credentials);
        expect(result?.expiresAt, now.add(const Duration(minutes: 5)));
        expect(
          result!.toJson().keys,
          containsAll(<String>['method', 'expiresAt']),
        );
        expect(result.toJson().toString(), isNot(contains(_signingKey)));
        expect(
          result.toJson().toString(),
          isNot(
            contains(RegExp(r'user@example\.com|user-1|phone|token-secret')),
          ),
        );
      },
    );

    test(
      'maps all generic lifecycle method labels without route branches',
      () async {
        const labels = <String, AuthLastAuthenticationMethodId>{
          'credentials': AuthLastAuthenticationMethodId.credentials,
          'username_password': AuthLastAuthenticationMethodId.usernamePassword,
          'phone': AuthLastAuthenticationMethodId.phone,
          'email_otp': AuthLastAuthenticationMethodId.emailOtp,
          'anonymous': AuthLastAuthenticationMethodId.anonymous,
          'webauthn': AuthLastAuthenticationMethodId.passkey,
        };

        for (final entry in labels.entries) {
          await plugin.onAuthenticationLifecycleEvent(
            AuthAuthenticationLifecycleEvent<String>(
              type:
                  AuthAuthenticationLifecycleEventType.authenticationSucceeded,
              context: 'browser',
              strategy: AuthSessionStrategy.session,
              authenticationMethod: entry.key,
            ),
          );
          expect((await plugin.read('browser'))?.method, entry.value);
        }

        await plugin.onAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.jwt,
            authenticationMethod: 'provider-label',
            oauthProviderNamespace: 'google',
          ),
        );
        expect(
          (await plugin.read('browser'))?.method,
          AuthLastAuthenticationMethodId.oauthProvider('google'),
        );
      },
    );

    test(
      'failed, unknown, and disallowed authentication do not update state',
      () async {
        expect(await plugin.read('browser'), isNull);
        await plugin.onAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.session,
            authenticationMethod: 'not-allowlisted',
          ),
        );
        expect(store.last, isNull);

        // A failed host authentication emits no successful lifecycle event.
        expect(await plugin.read('browser'), isNull);
      },
    );

    test('logout and both deletion lifecycle events clear state', () async {
      await plugin.onAuthenticationLifecycleEvent(
        const AuthAuthenticationLifecycleEvent<String>(
          type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
          context: 'browser',
          strategy: AuthSessionStrategy.session,
          authenticationMethod: 'credentials',
        ),
      );
      expect(await plugin.read('browser'), isNotNull);

      for (final type in <AuthAuthenticationLifecycleEventType>[
        AuthAuthenticationLifecycleEventType.signedOut,
        AuthAuthenticationLifecycleEventType.accountDeleted,
      ]) {
        await plugin.onAuthenticationLifecycleEvent(
          AuthAuthenticationLifecycleEvent<String>(
            type: type,
            context: 'browser',
            strategy: AuthSessionStrategy.session,
          ),
        );
        expect(store.last!.maxAge, 0);
        expect(store.last!.value, isEmpty);
        expect(await plugin.read('browser'), isNull);
        await plugin.onAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.session,
            authenticationMethod: 'credentials',
          ),
        );
      }
    });

    test(
      'session persistence omits Max-Age while retaining bounded expiry',
      () async {
        final sessionPlugin = AuthLastAuthenticationMethodPlugin<String>(
          signingKey: _signingKey,
          browserStore: store,
          policy: AuthLastAuthenticationMethodPolicy(
            allowedMethods: {AuthLastAuthenticationMethodId.credentials},
            browserPersistence:
                AuthLastAuthenticationMethodBrowserPersistence.session,
            retention: const Duration(minutes: 2),
          ),
          clock: () => now,
        );
        await sessionPlugin.onAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.session,
            authenticationMethod: 'credentials',
          ),
        );
        expect(store.last!.maxAge, isNull);
        expect(
          (await sessionPlugin.read('browser'))?.expiresAt,
          now.add(const Duration(minutes: 2)),
        );
      },
    );

    test(
      'tampered, injected, malformed, oversized, and expired state fails closed',
      () async {
        await plugin.onAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.session,
            authenticationMethod: 'credentials',
          ),
        );
        final original = store.last!.value;

        for (final invalid in <String>[
          '${original.substring(0, original.length - 1)}x',
          'v1|credentials|${now.microsecondsSinceEpoch}',
          'a' * 513,
          '!!!.!!!',
        ]) {
          store.last = AuthLastAuthenticationMethodCookie(
            name: plugin.policy.cookieName,
            value: invalid,
            path: plugin.policy.cookiePath,
            sameSite: plugin.policy.sameSite,
          );
          expect(await plugin.read('browser'), isNull, reason: invalid);
          expect(store.last!.maxAge, 0);
        }

        store.last = AuthLastAuthenticationMethodCookie(
          name: plugin.policy.cookieName,
          value: original,
          path: plugin.policy.cookiePath,
          sameSite: plugin.policy.sameSite,
        );
        now = now.add(const Duration(minutes: 5));
        expect(await plugin.read('browser'), isNull);
        expect(store.last!.maxAge, 0);
      },
    );

    test(
      'property: arbitrary injected cookie values never become a method',
      () async {
        final runner = PropertyTestRunner<String>(
          Chaos.string(minLength: 0, maxLength: 1024),
          (value) async {
            store.last = AuthLastAuthenticationMethodCookie(
              name: plugin.policy.cookieName,
              value: '!$value',
              path: plugin.policy.cookiePath,
              sameSite: plugin.policy.sameSite,
            );
            expect(await plugin.read('browser'), isNull);
            expect(store.last!.maxAge, 0);
          },
          PropertyConfig(numTests: 250, seed: 20260820),
        );
        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );

    test(
      'property: context secrets are never serialized into signed state',
      () async {
        final runner = PropertyTestRunner<String>(
          Chaos.string(minLength: 1, maxLength: 128),
          (secretContext) async {
            final secretMarker = 'secret-context:$secretContext';
            await plugin.onAuthenticationLifecycleEvent(
              AuthAuthenticationLifecycleEvent<String>(
                type: AuthAuthenticationLifecycleEventType
                    .authenticationSucceeded,
                context: secretMarker,
                strategy: AuthSessionStrategy.session,
                authenticationMethod: 'credentials',
              ),
            );
            final signedState = store.last!.value;
            final body = signedState.split('.').first;
            final padding = (4 - body.length % 4) % 4;
            final payload = utf8.decode(
              base64Url.decode('$body${'=' * padding}'),
            );
            expect(payload.split('|'), hasLength(3));
            expect(payload, startsWith('v1|credentials|'));
            expect(payload, isNot(contains(secretMarker)));
            expect(signedState, isNot(contains(_signingKey)));
          },
          PropertyConfig(numTests: 250, seed: 20260821),
        );
        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );

    test('browser adapter failures do not invalidate completed auth', () async {
      final resilientPlugin = AuthLastAuthenticationMethodPlugin<String>(
        signingKey: _signingKey,
        browserStore: _ThrowingCookieStore(),
        policy: AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
        ),
      );

      await expectLater(
        resilientPlugin.onAuthenticationLifecycleEvent(
          const AuthAuthenticationLifecycleEvent<String>(
            type: AuthAuthenticationLifecycleEventType.authenticationSucceeded,
            context: 'browser',
            strategy: AuthSessionStrategy.jwt,
            authenticationMethod: 'credentials',
          ),
        ),
        completes,
      );
      expect(await resilientPlugin.read('browser'), isNull);
    });
  });

  test(
    'server plugin conforms to the typed endpoint and client-operation contracts',
    () async {
      final plugin = AuthLastAuthenticationMethodPlugin<String>(
        signingKey: _signingKey,
        browserStore: _CookieStore(),
        policy: AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
        ),
      );
      final runtime = AuthRuntime<String>(
        options: AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          plugins: <AuthServerPlugin<String>>[plugin],
        ),
      );
      final suite = AuthPluginConformanceSuite<String>.fromRuntime(runtime);
      for (final conformanceCase in suite.cases) {
        final result = await conformanceCase.run();
        expect(result.isPassed, isTrue, reason: conformanceCase.id);
      }
    },
  );
}

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return <Object?>[
    'Property failed after ${result.numTests} cases',
    'Input: ${result.originalFailingInput}',
    'Shrunk: ${result.failingInput}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}
