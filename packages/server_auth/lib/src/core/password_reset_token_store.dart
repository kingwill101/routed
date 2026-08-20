import 'dart:async';

import 'tokens.dart' show hashOpaqueToken, secureRandomToken;

/// Persisted password-reset challenge metadata.
///
/// [tokenHash] is the digest of the one-time token sent to the user. The raw
/// token must never cross this persistence boundary.
class AuthPasswordResetToken {
  AuthPasswordResetToken({
    required this.userId,
    required this.tokenHash,
    required this.createdAt,
    required this.expiresAt,
  });

  final String userId;
  final String tokenHash;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isActive({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return current.isBefore(expiresAt.toUtc());
  }
}

/// Persistence boundary for single-use password-reset tokens.
abstract interface class AuthPasswordResetTokenStore {
  /// Stores [token], invalidating any older reset token for the same user.
  FutureOr<void> save(AuthPasswordResetToken token);

  /// Atomically consumes a raw reset token, returning its metadata once.
  ///
  /// Implementations must hash [token], check expiry, and delete the matching
  /// record as one atomic operation. A read-then-delete implementation is not
  /// replay-safe under concurrent reset requests.
  FutureOr<AuthPasswordResetToken?> consume(String token);

  /// Returns active token metadata without consuming or extending it.
  ///
  /// This capability is required so account policy can be checked before the
  /// one-time token is consumed.
  FutureOr<AuthPasswordResetToken?> findActive(String token);

  /// Invalidates all outstanding reset tokens for [userId].
  FutureOr<void> deleteForUser(String userId);
}

/// In-memory password-reset token store for tests and local development.
class InMemoryAuthPasswordResetTokenStore
    implements AuthPasswordResetTokenStore {
  InMemoryAuthPasswordResetTokenStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Map<String, AuthPasswordResetToken> _tokens =
      <String, AuthPasswordResetToken>{};
  final DateTime Function() _clock;

  @override
  Future<void> save(AuthPasswordResetToken token) async {
    _validate(token);
    _tokens.removeWhere((_, existing) => existing.userId == token.userId);
    _tokens[token.tokenHash] = token;
  }

  @override
  Future<AuthPasswordResetToken?> consume(String token) async {
    if (token.trim().isEmpty) return null;
    final record = _tokens.remove(hashOpaqueToken(token));
    if (record == null ||
        !_clock().toUtc().isBefore(record.expiresAt.toUtc())) {
      return null;
    }
    return record;
  }

  @override
  Future<AuthPasswordResetToken?> findActive(String token) async {
    if (token.trim().isEmpty) return null;
    final record = _tokens[hashOpaqueToken(token)];
    if (record == null ||
        !_clock().toUtc().isBefore(record.expiresAt.toUtc())) {
      return null;
    }
    return record;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    _tokens.removeWhere((_, token) => token.userId == normalizedUserId);
  }

  static void _validate(AuthPasswordResetToken token) {
    if (token.userId.trim().isEmpty) {
      throw ArgumentError.value(token.userId, 'token.userId');
    }
    if (token.tokenHash.trim().isEmpty) {
      throw ArgumentError.value(token.tokenHash, 'token.tokenHash');
    }
    if (!token.expiresAt.isAfter(token.createdAt)) {
      throw ArgumentError.value(
        token.expiresAt,
        'token.expiresAt',
        'must be after createdAt',
      );
    }
  }
}

/// Generates a raw password-reset token for delivery to the user.
String generateAuthPasswordResetToken({int length = 32}) {
  final token = secureRandomToken(length: length);
  if (token.trim().isEmpty) {
    throw StateError('Password-reset token generation returned an empty token');
  }
  return token;
}

/// Builds persistable password-reset metadata from a raw delivery token.
AuthPasswordResetToken buildAuthPasswordResetToken({
  required String userId,
  required String token,
  required Duration ttl,
  DateTime? now,
}) {
  if (userId.trim().isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  if (token.trim().isEmpty) {
    throw ArgumentError.value(token, 'token', 'must be non-empty');
  }
  if (ttl <= Duration.zero) {
    throw ArgumentError.value(ttl, 'ttl', 'must be greater than zero');
  }
  final createdAt = (now ?? DateTime.now()).toUtc();
  return AuthPasswordResetToken(
    userId: userId.trim(),
    tokenHash: hashOpaqueToken(token),
    createdAt: createdAt,
    expiresAt: createdAt.add(ttl),
  );
}

/// Consumes a raw password-reset token from the configured typed store.
Future<AuthPasswordResetToken?> consumeAuthPasswordResetToken({
  required AuthPasswordResetTokenStore store,
  required String token,
}) => Future.sync(() => store.consume(token));
