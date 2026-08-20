import 'dart:async';

import 'models.dart';
import 'store.dart';
import 'tokens.dart' show hashOpaqueToken;

/// Bounded in-memory email-change token store for tests and local development.
///
/// Only token digests are retained. Production stores must provide the same
/// atomic consume and expiry guarantees.
final class InMemoryAuthEmailChangeTokenStore
    implements
        AuthEmailChangeTokenStore,
        AuthEmailChangeTokenConditionalDeleteStore {
  InMemoryAuthEmailChangeTokenStore({
    DateTime Function()? clock,
    this.maxTokens = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxTokens < 1) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
  }

  final DateTime Function() _clock;
  final int maxTokens;
  final Map<String, _EmailChangeRecord> _records =
      <String, _EmailChangeRecord>{};

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

  @override
  Future<void> deleteForUser(String userId) async {
    final normalized = userId.trim();
    _records.removeWhere((_, record) => record.userId == normalized);
  }

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
