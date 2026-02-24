import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('authPrincipalAttribute remains stable', () {
    expect(authPrincipalAttribute, equals('auth.principal'));
  });

  test('parseAuthSessionIssuedAt parses ISO timestamp to UTC', () {
    final parsed = parseAuthSessionIssuedAt('2026-02-24T10:30:00Z');
    expect(parsed, isNotNull);
    expect(parsed!.isUtc, isTrue);
    expect(parseAuthSessionIssuedAt(null), isNull);
    expect(parseAuthSessionIssuedAt(''), isNull);
    expect(parseAuthSessionIssuedAt('invalid'), isNull);
  });

  test('serializeAuthSessionIssuedAt writes UTC ISO timestamps', () {
    final value = serializeAuthSessionIssuedAt(
      DateTime.parse('2026-02-24T12:00:00-05:00'),
    );
    expect(value, equals('2026-02-24T17:00:00.000Z'));
  });

  test('shouldRefreshAuthSession compares update age threshold', () {
    final now = DateTime.utc(2026, 2, 24, 12);
    final issuedAt = now.subtract(const Duration(minutes: 10));

    expect(
      shouldRefreshAuthSession(issuedAt, const Duration(minutes: 5), now: now),
      isTrue,
    );
    expect(
      shouldRefreshAuthSession(issuedAt, const Duration(minutes: 15), now: now),
      isFalse,
    );
  });

  test('authSessionRefreshAction resolves initialize/refresh/keep', () {
    final now = DateTime.utc(2026, 2, 24, 12);
    final oldIssuedAt = now.subtract(const Duration(minutes: 10));
    final recentIssuedAt = now.subtract(const Duration(minutes: 1));

    expect(
      authSessionRefreshAction(
        issuedAtValue: null,
        updateAge: const Duration(minutes: 5),
        now: now,
      ),
      AuthSessionRefreshAction.initialize,
    );
    expect(
      authSessionRefreshAction(
        issuedAtValue: serializeAuthSessionIssuedAt(oldIssuedAt),
        updateAge: const Duration(minutes: 5),
        now: now,
      ),
      AuthSessionRefreshAction.refresh,
    );
    expect(
      authSessionRefreshAction(
        issuedAtValue: serializeAuthSessionIssuedAt(recentIssuedAt),
        updateAge: const Duration(minutes: 5),
        now: now,
      ),
      AuthSessionRefreshAction.keep,
    );
  });

  test('resolveAuthSessionExpiry prefers explicit max age', () {
    final now = DateTime.utc(2026, 2, 24, 12);

    final explicit = resolveAuthSessionExpiry(
      sessionMaxAge: const Duration(hours: 2),
      sessionOptionsMaxAgeSeconds: 30,
      now: now,
    );
    final runtime = resolveAuthSessionExpiry(
      sessionOptionsMaxAgeSeconds: 120,
      now: now,
    );
    final none = resolveAuthSessionExpiry(
      sessionOptionsMaxAgeSeconds: 0,
      now: now,
    );

    expect(explicit, equals(now.add(const Duration(hours: 2))));
    expect(runtime, equals(now.add(const Duration(seconds: 120))));
    expect(none, isNull);
  });

  test('InMemoryRememberTokenStore saves and reads principals', () async {
    final store = InMemoryRememberTokenStore();
    final principal = AuthPrincipal(id: 'user-1', roles: const ['admin']);
    final expiry = DateTime.now().add(const Duration(minutes: 5));

    await store.save('token-1', principal, expiry);
    final restored = await store.read('token-1');

    expect(restored, isNotNull);
    expect(restored!.id, equals('user-1'));
    expect(restored.roles, contains('admin'));
  });

  test('InMemoryRememberTokenStore evicts expired tokens', () async {
    final store = InMemoryRememberTokenStore();
    final principal = AuthPrincipal(id: 'user-2', roles: const ['user']);
    final expiry = DateTime.now().subtract(const Duration(seconds: 1));

    await store.save('expired', principal, expiry);
    final restored = await store.read('expired');

    expect(restored, isNull);
  });
}
