import 'dart:async';

import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/tokens.dart'
    show hashOpaqueToken, secureRandomToken;

/// Persisted password-reset challenge metadata.
///
/// [tokenHash] is the digest of the one-time token sent to the user. The raw
/// token must never cross this persistence boundary.
class AuthPasswordResetToken {
  /// Creates reset metadata at the persistence boundary.
  ///
  /// [tokenHash] must be a digest rather than the raw token. Callers should
  /// provide UTC timestamps; the builders in this library normalize them.
  AuthPasswordResetToken({
    required this.userId,
    required this.tokenHash,
    required this.createdAt,
    required this.expiresAt,
  });

  /// User identifier to which this reset token belongs.
  final String userId;

  /// Digest of the raw one-time token sent to the user.
  final String tokenHash;

  /// UTC time at which this reset token was created.
  final DateTime createdAt;

  /// UTC time after which this reset token cannot be consumed.
  final DateTime expiresAt;

  /// Whether this token is active at [now].
  ///
  /// The comparison is strict: a token is active only while `now` is before
  /// [expiresAt]. This check does not consume or modify the token.
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
    implements AuthPasswordResetTokenStore, AuthInMemoryDeletionState {
  /// Creates an in-memory store using [clock] for expiry checks.
  ///
  /// This implementation keeps one record per exact user ID and stores the
  /// digest supplied in each [AuthPasswordResetToken].
  InMemoryAuthPasswordResetTokenStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Map<String, AuthPasswordResetToken> _tokens =
      <String, AuthPasswordResetToken>{};
  final DateTime Function() _clock;

  /// Captures the stored records for rollback by a deletion transaction.
  @override
  Object captureDeletionState() =>
      Map<String, AuthPasswordResetToken>.of(_tokens);

  /// Restores a snapshot produced by [captureDeletionState].
  ///
  /// Throws a [TypeError] when [state] is not this store's snapshot shape.
  @override
  void restoreDeletionState(Object state) {
    _tokens
      ..clear()
      ..addAll(state as Map<String, AuthPasswordResetToken>);
  }

  /// Saves [token], replacing any prior record for its exact user ID.
  ///
  /// Blank IDs or digests, and an expiry not after creation, throw an
  /// [ArgumentError]. The store retains the supplied digest and does not
  /// normalize the user ID.
  @override
  Future<void> save(AuthPasswordResetToken token) async {
    _validate(token);
    _tokens.removeWhere((_, existing) => existing.userId == token.userId);
    _tokens[token.tokenHash] = token;
  }

  /// Atomically consumes a matching active raw reset [token].
  ///
  /// The digest is removed before expiry is checked, so an expired token is
  /// not replayable. Returns null for blank, unknown, or expired tokens.
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

  /// Finds active metadata for [token] without consuming it.
  ///
  /// Returns null for blank, unknown, or expired tokens. A successful lookup
  /// leaves the stored record unchanged.
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

  /// Deletes all reset records whose stored user ID equals [userId].
  ///
  /// The lookup argument is trimmed; a blank value performs no deletion.
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
///
/// [length] is passed to [secureRandomToken]; invalid lengths throw the
/// helper's [ArgumentError]. The raw result is intended for delivery only and
/// must be hashed before persistence.
String generateAuthPasswordResetToken({int length = 32}) {
  final token = secureRandomToken(length: length);
  if (token.trim().isEmpty) {
    throw StateError('Password-reset token generation returned an empty token');
  }
  return token;
}

/// Builds persistable password-reset metadata from a raw delivery token.
///
/// Trims [userId], hashes [token] without storing its raw value, and creates
/// UTC timestamps from [now] plus [ttl]. Blank values and a non-positive [ttl]
/// throw an [ArgumentError].
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
///
/// Delegates to [AuthPasswordResetTokenStore.consume] and returns null when
/// the token is blank, unknown, expired, or already consumed.
Future<AuthPasswordResetToken?> consumeAuthPasswordResetToken({
  required AuthPasswordResetTokenStore store,
  required String token,
}) => Future.sync(() => store.consume(token));
