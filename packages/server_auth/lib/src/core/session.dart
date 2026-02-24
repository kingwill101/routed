import 'dart:async';
import 'dart:io';

import 'models.dart';
import 'tokens.dart' show secureRandomToken;

/// Attribute key used to store the authenticated principal in request context.
const String authPrincipalAttribute = 'auth.principal';

/// Session key used to store auth session issued-at timestamps.
const String authSessionIssuedAtKey = '_auth.session.issued_at';

/// Parses an ISO-8601 session issued-at timestamp into UTC.
DateTime? parseAuthSessionIssuedAt(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

/// Session refresh action derived from issued-at metadata.
enum AuthSessionRefreshAction { initialize, refresh, keep }

/// Serializes issued-at timestamps for auth session metadata.
String serializeAuthSessionIssuedAt(DateTime issuedAt) {
  return issuedAt.toUtc().toIso8601String();
}

/// Returns true when a session should be refreshed based on [updateAge].
bool shouldRefreshAuthSession(
  DateTime issuedAt,
  Duration updateAge, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toUtc();
  return current.difference(issuedAt.toUtc()) >= updateAge;
}

/// Decides whether auth session issued-at metadata should be initialized,
/// refreshed, or left unchanged.
AuthSessionRefreshAction authSessionRefreshAction({
  required String? issuedAtValue,
  required Duration updateAge,
  DateTime? now,
}) {
  final issuedAt = parseAuthSessionIssuedAt(issuedAtValue);
  if (issuedAt == null) {
    return AuthSessionRefreshAction.initialize;
  }
  return shouldRefreshAuthSession(issuedAt, updateAge, now: now)
      ? AuthSessionRefreshAction.refresh
      : AuthSessionRefreshAction.keep;
}

/// Applies issued-at refresh semantics with adapter hooks for write/touch.
void syncAuthSessionRefresh({
  required String? issuedAtValue,
  required Duration? updateAge,
  DateTime? now,
  required void Function(DateTime issuedAtUtc) writeIssuedAt,
  void Function()? touchSession,
}) {
  final age = updateAge;
  if (age == null) {
    return;
  }

  final current = (now ?? DateTime.now()).toUtc();
  final action = authSessionRefreshAction(
    issuedAtValue: issuedAtValue,
    updateAge: age,
    now: current,
  );

  switch (action) {
    case AuthSessionRefreshAction.initialize:
      writeIssuedAt(current);
      return;
    case AuthSessionRefreshAction.refresh:
      writeIssuedAt(current);
      touchSession?.call();
      return;
    case AuthSessionRefreshAction.keep:
      return;
  }
}

/// Resolves auth session expiry from explicit or runtime max-age settings.
DateTime? resolveAuthSessionExpiry({
  Duration? sessionMaxAge,
  int? sessionOptionsMaxAgeSeconds,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (sessionMaxAge != null) {
    return current.add(sessionMaxAge);
  }
  final maxAge = sessionOptionsMaxAgeSeconds;
  if (maxAge == null || maxAge <= 0) {
    return null;
  }
  return current.add(Duration(seconds: maxAge));
}

/// Resolves positive session max-age seconds from a duration.
int? resolveAuthSessionMaxAgeSeconds(Duration? sessionMaxAge) {
  if (sessionMaxAge == null) {
    return null;
  }
  final seconds = sessionMaxAge.inSeconds;
  if (seconds <= 0) {
    return null;
  }
  return seconds;
}

/// Builds an HTTP-only remember-token cookie.
Cookie buildRememberTokenCookie(
  String cookieName,
  String token, {
  required DateTime expiresAt,
  String path = '/',
  String? domain,
  bool secure = false,
  SameSite? sameSite,
  bool httpOnly = true,
}) {
  final cookie = Cookie(cookieName, token)
    ..httpOnly = httpOnly
    ..expires = expiresAt
    ..path = path;
  if (domain != null && domain.isNotEmpty) {
    cookie.domain = domain;
  }
  if (secure) {
    cookie.secure = true;
  }
  if (sameSite != null) {
    cookie.sameSite = sameSite;
  }
  return cookie;
}

/// Builds an expired remember-token cookie for logout/invalidations.
Cookie buildExpiredRememberTokenCookie(
  String cookieName, {
  String path = '/',
  String? domain,
  bool secure = false,
  SameSite? sameSite,
  bool httpOnly = true,
}) {
  final cookie = buildRememberTokenCookie(
    cookieName,
    '',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    path: path,
    domain: domain,
    secure: secure,
    sameSite: sameSite,
    httpOnly: httpOnly,
  );
  cookie.maxAge = 0;
  return cookie;
}

/// Persistence contract for long-lived "remember me" tokens.
abstract class RememberTokenStore {
  FutureOr<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  );

  FutureOr<AuthPrincipal?> read(String token);

  FutureOr<void> remove(String token);
}

class InMemoryRememberTokenStore implements RememberTokenStore {
  final Map<String, _RememberRecord> _storage = <String, _RememberRecord>{};

  @override
  Future<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  ) async {
    _storage[token] = _RememberRecord(principal, expiresAt);
  }

  @override
  Future<AuthPrincipal?> read(String token) async {
    final record = _storage[token];
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      _storage.remove(token);
      return null;
    }
    return record.principal;
  }

  @override
  Future<void> remove(String token) async {
    _storage.remove(token);
  }
}

class _RememberRecord {
  _RememberRecord(this.principal, this.expiresAt);

  final AuthPrincipal principal;
  final DateTime expiresAt;
}

/// Adapter used by [RememberSessionAuthRuntime] to read/write framework state.
abstract class AuthSessionRuntimeAdapter<TContext> {
  AuthPrincipal? readPrincipalAttribute(TContext context, String attributeKey);

  void writePrincipalAttribute(
    TContext context,
    String attributeKey,
    AuthPrincipal? principal,
  );

  Map<String, dynamic>? readSessionPrincipal(
    TContext context,
    String sessionKey,
  );

  void writeSessionPrincipal(
    TContext context,
    String sessionKey,
    Map<String, dynamic>? principalJson,
  );

  Iterable<Cookie> requestCookies(TContext context);

  void setResponseCookie(TContext context, Cookie cookie);

  Cookie buildRememberCookie(
    TContext context,
    String cookieName,
    String token,
    DateTime expiresAt,
  );

  Cookie buildExpiredRememberCookie(TContext context, String cookieName);
}

/// Framework-agnostic remember-me + session principal runtime.
///
/// Framework adapters are responsible for providing a concrete
/// [AuthSessionRuntimeAdapter] that maps framework request/session/cookie
/// semantics to this runtime.
class RememberSessionAuthRuntime<TContext> {
  RememberSessionAuthRuntime({
    required this.adapter,
    RememberTokenStore? rememberStore,
    this.rememberCookieName = 'remember_token',
    this.defaultRememberDuration = const Duration(days: 30),
    this.sessionPrincipalKey = '__auth.principal',
    this.principalAttributeKey = authPrincipalAttribute,
    this.tokenGenerator = secureRandomToken,
    DateTime Function()? clock,
  }) : rememberStore = rememberStore ?? InMemoryRememberTokenStore(),
       _clock = clock ?? DateTime.now;

  final AuthSessionRuntimeAdapter<TContext> adapter;
  final RememberTokenStore rememberStore;
  final String rememberCookieName;
  final Duration defaultRememberDuration;
  final String sessionPrincipalKey;
  final String principalAttributeKey;
  final String Function() tokenGenerator;
  final DateTime Function() _clock;

  Future<void> login(
    TContext context,
    AuthPrincipal principal, {
    bool rememberMe = false,
    Duration? rememberDuration,
  }) async {
    adapter.writeSessionPrincipal(
      context,
      sessionPrincipalKey,
      principal.toJson(),
    );
    adapter.writePrincipalAttribute(context, principalAttributeKey, principal);

    if (!rememberMe) {
      return;
    }

    final existing = _findRequestCookie(context);
    if (existing != null && existing.value.isNotEmpty) {
      await Future.sync(() => rememberStore.remove(existing.value));
    }

    final token = tokenGenerator();
    final expiresAt = _clock().add(rememberDuration ?? defaultRememberDuration);
    await Future.sync(() => rememberStore.save(token, principal, expiresAt));
    adapter.setResponseCookie(
      context,
      adapter.buildRememberCookie(
        context,
        rememberCookieName,
        token,
        expiresAt,
      ),
    );
  }

  Future<void> logout(TContext context) async {
    adapter.writeSessionPrincipal(context, sessionPrincipalKey, null);
    adapter.writePrincipalAttribute(context, principalAttributeKey, null);

    final cookie = _findRequestCookie(context);
    if (cookie != null && cookie.value.isNotEmpty) {
      await Future.sync(() => rememberStore.remove(cookie.value));
    }
    adapter.setResponseCookie(
      context,
      adapter.buildExpiredRememberCookie(context, rememberCookieName),
    );
  }

  AuthPrincipal? current(TContext context) {
    final cached = adapter.readPrincipalAttribute(
      context,
      principalAttributeKey,
    );
    if (cached != null) {
      return cached;
    }

    final stored = adapter.readSessionPrincipal(context, sessionPrincipalKey);
    if (stored == null) {
      return null;
    }

    final principal = AuthPrincipal.fromJson(stored);
    adapter.writePrincipalAttribute(context, principalAttributeKey, principal);
    return principal;
  }

  /// Hydrates auth principal from session or remember-token cookie.
  ///
  /// - If session principal exists, request attribute is refreshed.
  /// - If remember-token cookie is valid, session principal is restored and the
  ///   remember token is rotated.
  /// - If remember-token cookie is invalid/expired, it is revoked.
  Future<void> hydrate(TContext context) async {
    final sessionData = adapter.readSessionPrincipal(
      context,
      sessionPrincipalKey,
    );
    if (sessionData != null) {
      adapter.writePrincipalAttribute(
        context,
        principalAttributeKey,
        AuthPrincipal.fromJson(sessionData),
      );
      return;
    }

    final rememberCookie = _findRequestCookie(context);
    if (rememberCookie == null || rememberCookie.value.isEmpty) {
      return;
    }

    final principal = await Future.sync(
      () => rememberStore.read(rememberCookie.value),
    );
    if (principal == null) {
      await Future.sync(() => rememberStore.remove(rememberCookie.value));
      adapter.setResponseCookie(
        context,
        adapter.buildExpiredRememberCookie(context, rememberCookieName),
      );
      return;
    }

    adapter.writeSessionPrincipal(
      context,
      sessionPrincipalKey,
      principal.toJson(),
    );
    adapter.writePrincipalAttribute(context, principalAttributeKey, principal);

    final rotatedToken = tokenGenerator();
    final newExpiry = _clock().add(defaultRememberDuration);
    await Future.sync(
      () => rememberStore.save(rotatedToken, principal, newExpiry),
    );
    await Future.sync(() => rememberStore.remove(rememberCookie.value));
    adapter.setResponseCookie(
      context,
      adapter.buildRememberCookie(
        context,
        rememberCookieName,
        rotatedToken,
        newExpiry,
      ),
    );
  }

  Cookie? _findRequestCookie(TContext context) {
    for (final cookie in adapter.requestCookies(context)) {
      if (cookie.name == rememberCookieName) {
        return cookie;
      }
    }
    return null;
  }
}
