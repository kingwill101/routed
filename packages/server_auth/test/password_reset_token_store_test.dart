import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('buildAuthPasswordResetToken stores only a digest', () {
    final now = DateTime.utc(2026, 8, 19, 12);
    final token = buildAuthPasswordResetToken(
      userId: 'user-1',
      token: 'reset-secret',
      ttl: const Duration(minutes: 10),
      now: now,
    );

    expect(token.userId, equals('user-1'));
    expect(token.tokenHash, equals(hashOpaqueToken('reset-secret')));
    expect(token.tokenHash, isNot(contains('reset-secret')));
    expect(token.createdAt, equals(now));
    expect(token.expiresAt, equals(now.add(const Duration(minutes: 10))));
  });

  test(
    'in-memory reset tokens replace older tokens for the same user',
    () async {
      final now = DateTime.utc(2026, 8, 19, 12);
      final store = InMemoryAuthPasswordResetTokenStore(clock: () => now);
      final first = buildAuthPasswordResetToken(
        userId: 'user-1',
        token: 'first-secret',
        ttl: const Duration(minutes: 10),
        now: now,
      );
      final second = buildAuthPasswordResetToken(
        userId: 'user-1',
        token: 'second-secret',
        ttl: const Duration(minutes: 10),
        now: now,
      );

      await store.save(first);
      await store.save(second);

      expect(await store.consume('first-secret'), isNull);
      expect((await store.consume('second-secret'))?.userId, equals('user-1'));
    },
  );

  test('in-memory reset tokens are single-use under concurrency', () async {
    final now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthPasswordResetTokenStore(clock: () => now);
    await store.save(
      buildAuthPasswordResetToken(
        userId: 'user-1',
        token: 'one-time-secret',
        ttl: const Duration(minutes: 10),
        now: now,
      ),
    );

    final results = await Future.wait(
      List<Future<AuthPasswordResetToken?>>.generate(
        32,
        (_) => store.consume('one-time-secret'),
      ),
    );

    expect(results.whereType<AuthPasswordResetToken>(), hasLength(1));
    expect(await store.consume('one-time-secret'), isNull);
  });

  test('active reset-token lookup does not consume the token', () async {
    final now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthPasswordResetTokenStore(clock: () => now);
    await store.save(
      buildAuthPasswordResetToken(
        userId: 'user-1',
        token: 'lookup-secret',
        ttl: const Duration(minutes: 10),
        now: now,
      ),
    );

    expect((await store.findActive('lookup-secret'))?.userId, 'user-1');
    expect((await store.consume('lookup-secret'))?.userId, 'user-1');
  });

  test('in-memory reset tokens reject expiry and blank input', () async {
    var now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthPasswordResetTokenStore(clock: () => now);
    await store.save(
      buildAuthPasswordResetToken(
        userId: 'user-1',
        token: 'expired-secret',
        ttl: const Duration(minutes: 10),
        now: now,
      ),
    );

    now = now.add(const Duration(minutes: 10));
    expect(await store.consume('expired-secret'), isNull);
    expect(await store.consume('  '), isNull);
  });

  test('password-reset builders reject invalid configuration', () {
    expect(
      () => buildAuthPasswordResetToken(
        userId: ' ',
        token: 'secret',
        ttl: const Duration(minutes: 10),
      ),
      throwsArgumentError,
    );
    expect(
      () => buildAuthPasswordResetToken(
        userId: 'user-1',
        token: ' ',
        ttl: const Duration(minutes: 10),
      ),
      throwsArgumentError,
    );
    expect(
      () => buildAuthPasswordResetToken(
        userId: 'user-1',
        token: 'secret',
        ttl: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('CallbackAuthStore exposes the typed reset-token domain', () async {
    AuthPasswordResetToken? saved;
    var consumed = false;
    var deletedUserId = '';
    final store = CallbackAuthStore(
      onSavePasswordResetToken: (token) => saved = token,
      onConsumePasswordResetToken: (token) {
        consumed = token == 'raw-secret';
        return saved;
      },
      onFindPasswordResetToken: (_) => saved,
      onDeletePasswordResetTokens: (userId) => deletedUserId = userId,
    );
    final record = buildAuthPasswordResetToken(
      userId: 'user-1',
      token: 'raw-secret',
      ttl: const Duration(minutes: 10),
    );

    await store.passwordResetTokens.save(record);
    expect(
      await (store.passwordResetTokens as AuthPasswordResetTokenLookupStore)
          .findActive('raw-secret'),
      same(record),
    );
    expect(
      await store.passwordResetTokens.consume('raw-secret'),
      equals(record),
    );
    await store.passwordResetTokens.deleteForUser('user-1');

    expect(saved, same(record));
    expect(consumed, isTrue);
    expect(deletedUserId, equals('user-1'));
  });
}
