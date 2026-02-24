import 'dart:async';
import 'dart:io';

import 'models.dart';

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
