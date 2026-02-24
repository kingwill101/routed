import 'dart:io';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('authPrincipalAttribute remains stable', () {
    expect(authPrincipalAttribute, equals('auth.principal'));
  });

  test('authSessionIssuedAtKey remains stable', () {
    expect(authSessionIssuedAtKey, equals('_auth.session.issued_at'));
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

  test('syncAuthSessionRefresh no-ops when updateAge is null', () {
    var wrote = false;
    var touched = false;

    syncAuthSessionRefresh(
      issuedAtValue: null,
      updateAge: null,
      writeIssuedAt: (_) => wrote = true,
      touchSession: () => touched = true,
    );

    expect(wrote, isFalse);
    expect(touched, isFalse);
  });

  test('syncAuthSessionRefresh initializes issued-at without touching', () {
    DateTime? written;
    var touched = false;
    final now = DateTime.utc(2026, 2, 24, 12);

    syncAuthSessionRefresh(
      issuedAtValue: null,
      updateAge: const Duration(minutes: 5),
      now: now,
      writeIssuedAt: (value) => written = value,
      touchSession: () => touched = true,
    );

    expect(written, equals(now));
    expect(touched, isFalse);
  });

  test('syncAuthSessionRefresh refreshes issued-at and touches session', () {
    DateTime? written;
    var touched = false;
    final now = DateTime.utc(2026, 2, 24, 12);

    syncAuthSessionRefresh(
      issuedAtValue: serializeAuthSessionIssuedAt(
        now.subtract(const Duration(minutes: 10)),
      ),
      updateAge: const Duration(minutes: 5),
      now: now,
      writeIssuedAt: (value) => written = value,
      touchSession: () => touched = true,
    );

    expect(written, equals(now));
    expect(touched, isTrue);
  });

  test(
    'syncAuthSessionRefresh keeps current state when refresh is not due',
    () {
      DateTime? written;
      var touched = false;
      final now = DateTime.utc(2026, 2, 24, 12);

      syncAuthSessionRefresh(
        issuedAtValue: serializeAuthSessionIssuedAt(
          now.subtract(const Duration(minutes: 1)),
        ),
        updateAge: const Duration(minutes: 5),
        now: now,
        writeIssuedAt: (value) => written = value,
        touchSession: () => touched = true,
      );

      expect(written, isNull);
      expect(touched, isFalse);
    },
  );

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

  test('resolveAuthSessionMaxAgeSeconds returns positive seconds only', () {
    expect(resolveAuthSessionMaxAgeSeconds(null), isNull);
    expect(resolveAuthSessionMaxAgeSeconds(Duration.zero), isNull);
    expect(
      resolveAuthSessionMaxAgeSeconds(const Duration(minutes: 5)),
      equals(300),
    );
  });

  test('remember-token cookie builders apply options and expiration', () {
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));
    final cookie = buildRememberTokenCookie(
      'remember_token',
      'token-1',
      expiresAt: expiresAt,
      path: '/auth',
      domain: 'example.test',
      secure: true,
      sameSite: SameSite.lax,
    );
    final expired = buildExpiredRememberTokenCookie(
      'remember_token',
      path: '/auth',
      domain: 'example.test',
      secure: true,
      sameSite: SameSite.lax,
    );

    expect(cookie.name, equals('remember_token'));
    expect(cookie.value, equals('token-1'));
    expect(cookie.httpOnly, isTrue);
    expect(cookie.path, equals('/auth'));
    expect(cookie.domain, equals('example.test'));
    expect(cookie.secure, isTrue);
    expect(cookie.sameSite, equals(SameSite.lax));
    expect(cookie.expires, equals(expiresAt));

    expect(expired.value, equals(''));
    expect(expired.maxAge, equals(0));
    expect(expired.path, equals('/auth'));
    expect(expired.domain, equals('example.test'));
    expect(expired.secure, isTrue);
    expect(expired.sameSite, equals(SameSite.lax));
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

  test('RememberSessionAuthRuntime login/current/logout flow', () async {
    final context = _FakeSessionContext();
    final store = InMemoryRememberTokenStore();
    final runtime = RememberSessionAuthRuntime<_FakeSessionContext>(
      adapter: const _FakeSessionAdapter(),
      rememberStore: store,
      tokenGenerator: () => 'token-1',
      clock: () => DateTime.utc(2026, 2, 24, 12),
      sessionPrincipalKey: 'session.principal',
    );

    final principal = AuthPrincipal(id: 'user-1', roles: const ['admin']);

    await runtime.login(context, principal, rememberMe: true);
    expect(context.session['session.principal'], isA<Map<String, dynamic>>());
    expect((runtime.current(context))?.id, equals('user-1'));
    expect(context.responseCookies.last.value, equals('token-1'));
    expect((await store.read('token-1'))?.id, equals('user-1'));

    context.requestCookies
      ..clear()
      ..add(Cookie('remember_token', 'token-1'));
    await runtime.logout(context);
    expect(context.session.containsKey('session.principal'), isFalse);
    expect(context.attributes[authPrincipalAttribute], isNull);
    expect(await store.read('token-1'), isNull);
    expect(context.responseCookies.last.maxAge, equals(0));
  });

  test(
    'RememberSessionAuthRuntime hydrate restores and rotates remember token',
    () async {
      final context = _FakeSessionContext();
      final store = InMemoryRememberTokenStore();
      await store.save(
        'token-old',
        AuthPrincipal(id: 'user-2', roles: const <String>['user']),
        DateTime.now().add(const Duration(hours: 1)),
      );
      context.requestCookies.add(Cookie('remember_token', 'token-old'));

      final runtime = RememberSessionAuthRuntime<_FakeSessionContext>(
        adapter: const _FakeSessionAdapter(),
        rememberStore: store,
        tokenGenerator: () => 'token-new',
        clock: () => DateTime.utc(2026, 2, 24, 12),
        sessionPrincipalKey: 'session.principal',
      );

      await runtime.hydrate(context);
      expect((runtime.current(context))?.id, equals('user-2'));
      expect(await store.read('token-old'), isNull);
      expect((await store.read('token-new'))?.id, equals('user-2'));
      expect(context.responseCookies.last.value, equals('token-new'));
    },
  );

  test(
    'RememberSessionAuthRuntime hydrate expires invalid remember token',
    () async {
      final context = _FakeSessionContext();
      context.requestCookies.add(Cookie('remember_token', 'missing-token'));
      final runtime = RememberSessionAuthRuntime<_FakeSessionContext>(
        adapter: const _FakeSessionAdapter(),
        rememberStore: InMemoryRememberTokenStore(),
        sessionPrincipalKey: 'session.principal',
      );

      await runtime.hydrate(context);
      expect(context.session, isEmpty);
      expect(context.responseCookies.last.maxAge, equals(0));
    },
  );
}

class _FakeSessionContext {
  final Map<String, Object?> attributes = <String, Object?>{};
  final Map<String, dynamic> session = <String, dynamic>{};
  final List<Cookie> requestCookies = <Cookie>[];
  final List<Cookie> responseCookies = <Cookie>[];
}

class _FakeSessionAdapter
    implements AuthSessionRuntimeAdapter<_FakeSessionContext> {
  const _FakeSessionAdapter();

  @override
  Cookie buildExpiredRememberCookie(
    _FakeSessionContext context,
    String cookieName,
  ) {
    return buildExpiredRememberTokenCookie(cookieName, path: '/');
  }

  @override
  Cookie buildRememberCookie(
    _FakeSessionContext context,
    String cookieName,
    String token,
    DateTime expiresAt,
  ) {
    return buildRememberTokenCookie(
      cookieName,
      token,
      expiresAt: expiresAt,
      path: '/',
    );
  }

  @override
  AuthPrincipal? readPrincipalAttribute(
    _FakeSessionContext context,
    String attributeKey,
  ) {
    final value = context.attributes[attributeKey];
    if (value is AuthPrincipal) {
      return value;
    }
    return null;
  }

  @override
  Map<String, dynamic>? readSessionPrincipal(
    _FakeSessionContext context,
    String sessionKey,
  ) {
    final value = context.session[sessionKey];
    if (value is Map<String, dynamic>) {
      return value;
    }
    return null;
  }

  @override
  Iterable<Cookie> requestCookies(_FakeSessionContext context) {
    return context.requestCookies;
  }

  @override
  void setResponseCookie(_FakeSessionContext context, Cookie cookie) {
    context.responseCookies.add(cookie);
  }

  @override
  void writePrincipalAttribute(
    _FakeSessionContext context,
    String attributeKey,
    AuthPrincipal? principal,
  ) {
    if (principal == null) {
      context.attributes.remove(attributeKey);
      return;
    }
    context.attributes[attributeKey] = principal;
  }

  @override
  void writeSessionPrincipal(
    _FakeSessionContext context,
    String sessionKey,
    Map<String, dynamic>? principalJson,
  ) {
    if (principalJson == null) {
      context.session.remove(sessionKey);
      return;
    }
    context.session[sessionKey] = principalJson;
  }
}
