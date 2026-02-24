import 'dart:async';

import 'models.dart';

/// Attribute key used to store the authenticated principal in request context.
const String authPrincipalAttribute = 'auth.principal';

/// Parses an ISO-8601 session issued-at timestamp into UTC.
DateTime? parseAuthSessionIssuedAt(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
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
