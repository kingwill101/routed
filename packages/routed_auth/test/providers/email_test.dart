import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('MagicLinkPlugin', () {
    test('is opt-in provider metadata contributed by the plugin', () {
      final store = InMemoryAuthStore();
      final plugin = MagicLinkPlugin<EngineContext>(
        id: 'magic-link',
        name: 'Magic Link',
        sendMagicLink: (_) {},
      );
      final runtime = AuthRuntime<EngineContext>(
        options: AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: const [],
          plugins: [plugin],
        ),
      );

      expect(runtime.providers, contains(same(plugin)));
      expect(plugin.id, 'magic-link');
      expect(plugin.name, 'Magic Link');
      expect(plugin.type, AuthProviderType.email);
      expect(plugin.toJson(), {
        'id': 'magic-link',
        'name': 'Magic Link',
        'type': 'email',
      });
    });

    test(
      'delivers raw material only after digest-only issue commits',
      () async {
        final store = InMemoryAuthStore();
        AuthMagicLinkDelivery<EngineContext>? delivery;
        final plugin = MagicLinkPlugin<EngineContext>(
          sendMagicLink: (value) async {
            await Future<void>.delayed(Duration.zero);
            delivery = value;
          },
          tokenGenerator: () => 'one-time-raw-token',
        );
        AuthRuntime<EngineContext>(
          options: AuthOptions<EngineContext>(
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            providers: const [],
            plugins: [plugin],
          ),
        );

        final payload = await startAuthEmailSignIn<EngineContext>(
          backend: store,
          provider: plugin,
          context: _MockEngineContext(),
          email: ' User@Example.com ',
          callbackUrl: 'https://example.test/auth/callback/email',
          sessionStrategy: AuthSessionStrategy.session,
          now: DateTime.utc(2026),
        );

        expect(delivery?.email, 'user@example.com');
        expect(delivery?.token, 'one-time-raw-token');
        expect(payload.record.tokenHash, isNot('one-time-raw-token'));

        final first = await resolveAuthEmailVerificationSignIn(
          backend: store,
          providerId: plugin.id,
          email: delivery!.email,
          token: delivery!.token,
          now: DateTime.utc(2026),
          generateUserId: () => 'user-1',
        );
        final replay = await resolveAuthEmailVerificationSignIn(
          backend: store,
          providerId: plugin.id,
          email: delivery!.email,
          token: delivery!.token,
          now: DateTime.utc(2026),
          generateUserId: () => 'user-2',
        );

        expect(first?.user.id, 'user-1');
        expect(replay, isNull);
      },
    );

    test('rejects unsafe provider IDs and non-positive expiry', () {
      expect(
        () => MagicLinkPlugin<EngineContext>(
          id: '../email',
          sendMagicLink: (_) {},
        ),
        throwsArgumentError,
      );
      expect(
        () => MagicLinkPlugin<EngineContext>(
          tokenExpiry: Duration.zero,
          sendMagicLink: (_) {},
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _MockEngineContext implements EngineContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
