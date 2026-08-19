import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

AuthSessionRecord _session({
  required String id,
  required String userId,
  required String token,
  required DateTime now,
}) {
  return AuthSessionRecord(
    id: id,
    tokenHash: hashOpaqueToken(token),
    userId: userId,
    createdAt: now,
    expiresAt: now.add(const Duration(days: 30)),
    lastUsedAt: now,
    authenticationMethod: 'credentials',
    ipAddress: '192.0.2.1',
    userAgent: 'test-agent',
  );
}

void main() {
  test('lists active sessions without exposing token digests', () async {
    final store = InMemoryAuthStore();
    final now = DateTime.utc(2030);
    await store.sessions.create(
      _session(id: 'session-1', userId: 'user-1', token: 'token-1', now: now),
    );
    await store.sessions.create(
      _session(
        id: 'session-2',
        userId: 'user-1',
        token: 'token-2',
        now: now.add(const Duration(minutes: 1)),
      ),
    );
    await store.sessions.create(
      _session(
        id: 'other-user-session',
        userId: 'user-2',
        token: 'token-3',
        now: now,
      ),
    );

    final sessions = await listAuthSessionsForUser(
      store: store,
      userId: 'user-1',
      currentSessionId: 'session-1',
      now: now.add(const Duration(minutes: 2)),
    );

    expect(sessions, hasLength(2));
    expect(sessions.first.isCurrent, isTrue);
    expect(sessions.map((session) => session.userId), everyElement('user-1'));
    expect(sessions.first.toJson(), isNot(contains('tokenHash')));
    expect(sessions.first.toJson(), isNot(contains('token-1')));
  });

  test(
    'revoke-by-id enforces ownership and revoke-others preserves one',
    () async {
      final store = InMemoryAuthStore();
      final now = DateTime.utc(2030);
      await store.sessions.create(
        _session(id: 'current', userId: 'user-1', token: 'token-1', now: now),
      );
      await store.sessions.create(
        _session(id: 'other', userId: 'user-1', token: 'token-2', now: now),
      );
      await store.sessions.create(
        _session(id: 'foreign', userId: 'user-2', token: 'token-3', now: now),
      );

      expect(await store.sessions.revokeById('user-1', 'foreign'), isNull);
      expect(
        await store.sessions.revokeAllForUserExcept('user-1', 'current'),
        1,
      );
      expect(
        (await store.sessions.find(hashOpaqueToken('token-1')))?.revokedAt,
        isNull,
      );
      expect(
        (await store.sessions.find(hashOpaqueToken('token-2')))?.revokedAt,
        isNotNull,
      );
      expect(
        (await store.sessions.find(hashOpaqueToken('token-3')))?.revokedAt,
        isNull,
      );
    },
  );
}
