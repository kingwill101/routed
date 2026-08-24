import 'dart:async';

import 'deletion_transaction.dart';
import 'models.dart';
import 'store.dart';
import 'tokens.dart' show hashOpaqueToken;

/// Bounded in-memory email-change token store for tests and local development.
///
/// Token digests and the normalized user, email, and expiry metadata are
/// retained; the raw token is not. Production stores must provide the same
/// atomic consume and expiry guarantees.
final class InMemoryAuthEmailChangeTokenStore
    implements
        AuthEmailChangeTokenStore,
        AuthEmailChangeTokenConditionalDeleteStore,
        AuthInMemoryDeletionState {
  /// Creates a bounded store using [clock] for expiry checks.
  ///
  /// [maxTokens] must be positive. This implementation retains token digests
  /// with normalized user, email, and expiry metadata, prunes expired records
  /// on access, and evicts the oldest record when capacity is reached.
  InMemoryAuthEmailChangeTokenStore({
    DateTime Function()? clock,
    this.maxTokens = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxTokens < 1) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
  }

  final DateTime Function() _clock;

  /// Maximum number of token digests retained by this store.
  final int maxTokens;

  final Map<String, _EmailChangeRecord> _records =
      <String, _EmailChangeRecord>{};

  /// Captures the records for rollback by a deletion transaction.
  @override
  Object captureDeletionState() => Map<String, _EmailChangeRecord>.of(_records);

  /// Restores a snapshot produced by [captureDeletionState].
  ///
  /// Throws a [TypeError] when [state] is not this store's snapshot shape.
  @override
  void restoreDeletionState(Object state) {
    _records
      ..clear()
      ..addAll(state as Map<String, _EmailChangeRecord>);
  }

  /// Saves [token] after normalizing its user and email values.
  ///
  /// User IDs are trimmed, email addresses are trimmed and lower-cased, and
  /// only a digest of the raw token is retained. Existing records for the
  /// normalized user are replaced. Blank fields throw an [ArgumentError].
  /// Expired records are pruned and the oldest record is evicted at capacity.
  @override
  Future<void> save(AuthEmailChangeToken token) async {
    final userId = token.userId.trim();
    final email = token.newEmail.trim().toLowerCase();
    if (userId.isEmpty || email.isEmpty || token.token.trim().isEmpty) {
      throw ArgumentError('Email-change token fields must be non-empty.');
    }
    final now = _clock().toUtc();
    _prune(now);
    _records.removeWhere((_, record) => record.userId == userId);
    while (_records.length >= maxTokens) {
      _removeOldest();
    }
    _records[hashOpaqueToken(token.token)] = _EmailChangeRecord(
      userId: userId,
      newEmail: email,
      expiresAt: token.expiresAt.toUtc(),
    );
  }

  /// Consumes a matching unexpired token at most once.
  ///
  /// The raw [token] is hashed for lookup and removed before expiry is
  /// checked, so an expired or concurrently consumed token cannot be replayed.
  /// Returns metadata reconstructed with the supplied raw token, or null for a
  /// blank, unknown, or expired token.
  @override
  Future<AuthEmailChangeToken?> consume(String token) async {
    if (token.trim().isEmpty) return null;
    final now = _clock().toUtc();
    _prune(now);
    final record = _records.remove(hashOpaqueToken(token));
    if (record == null || !now.isBefore(record.expiresAt)) return null;
    return AuthEmailChangeToken(
      userId: record.userId,
      newEmail: record.newEmail,
      token: token,
      expiresAt: record.expiresAt,
    );
  }

  /// Deletes all stored email-change records for [userId].
  ///
  /// The lookup ID is trimmed; a blank ID performs no deletion.
  @override
  Future<void> deleteForUser(String userId) async {
    final normalized = userId.trim();
    _records.removeWhere((_, record) => record.userId == normalized);
  }

  /// Deletes one matching record for [userId] and [token].
  ///
  /// The operation compares the normalized user ID and token digest before
  /// removing anything, preserving newer records when an older delivery fails.
  /// Returns whether a matching record was removed.
  @override
  Future<bool> deleteTokenForUser(String userId, String token) async {
    final normalized = userId.trim();
    if (normalized.isEmpty || token.trim().isEmpty) return false;
    final digest = hashOpaqueToken(token);
    final record = _records[digest];
    if (record == null || record.userId != normalized) return false;
    _records.remove(digest);
    return true;
  }

  void _prune(DateTime now) {
    _records.removeWhere((_, record) => !now.isBefore(record.expiresAt));
  }

  void _removeOldest() {
    if (_records.isNotEmpty) _records.remove(_records.keys.first);
  }
}

final class _EmailChangeRecord {
  const _EmailChangeRecord({
    required this.userId,
    required this.newEmail,
    required this.expiresAt,
  });

  final String userId;
  final String newEmail;
  final DateTime expiresAt;
}
