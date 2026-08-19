import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'OAuth challenges are consumed at most once under concurrency',
    () async {
      final store = InMemoryAuthOAuthChallengeStore();
      final challenge = AuthOAuthChallenge(
        providerId: 'example',
        state: 'state-1',
        codeVerifier: 'verifier-1',
        nonce: 'nonce-1',
        callbackUrl: '/dashboard',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
      await store.save(challenge);

      final results = await Future.wait(
        List.generate(32, (_) => store.consume('example', 'state-1')),
      );

      expect(results.whereType<AuthOAuthChallenge>(), hasLength(1));
      expect(await store.consume('example', 'state-1'), isNull);
    },
  );

  test('OAuth challenges expire before they can be replayed', () async {
    var now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthOAuthChallengeStore(clock: () => now);
    await store.save(
      AuthOAuthChallenge(
        providerId: 'example',
        state: 'state-1',
        expiresAt: now.add(const Duration(minutes: 1)),
      ),
    );

    now = now.add(const Duration(minutes: 1));
    expect(await store.consume('example', 'state-1'), isNull);
  });

  test('OAuth challenge store evicts oldest entries at its capacity', () async {
    final store = InMemoryAuthOAuthChallengeStore(maxEntries: 2);
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 5));
    for (final state in ['state-1', 'state-2', 'state-3']) {
      await store.save(
        AuthOAuthChallenge(
          providerId: 'example',
          state: state,
          expiresAt: expiresAt,
        ),
      );
    }

    expect(await store.consume('example', 'state-1'), isNull);
    expect(await store.consume('example', 'state-2'), isNotNull);
    expect(await store.consume('example', 'state-3'), isNotNull);
  });

  test('OAuth challenge store removes expired entries while saving', () async {
    var now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthOAuthChallengeStore(
      clock: () => now,
      maxEntries: 2,
    );
    await store.save(
      AuthOAuthChallenge(
        providerId: 'example',
        state: 'expired',
        expiresAt: now.add(const Duration(minutes: 1)),
      ),
    );
    now = now.add(const Duration(minutes: 1));
    await store.save(
      AuthOAuthChallenge(
        providerId: 'example',
        state: 'fresh',
        expiresAt: now.add(const Duration(minutes: 1)),
      ),
    );

    expect(await store.consume('example', 'expired'), isNull);
    expect(await store.consume('example', 'fresh'), isNotNull);
  });
}
