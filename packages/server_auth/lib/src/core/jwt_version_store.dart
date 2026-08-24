import 'dart:async';

import 'package:server_auth/src/core/deletion_transaction.dart';

/// Persistence contract for per-user JWT session versions.
///
/// A JWT carries the version returned by [current]. Rotating the version
/// invalidates every previously issued JWT for that user without requiring
/// the application to enumerate or persist the individual tokens.
abstract interface class AuthJwtVersionStore {
  /// Returns the current version for [userId]. New users start at version 0.
  FutureOr<int> current(String userId);

  /// Atomically advances and returns the current version for [userId].
  FutureOr<int> rotate(String userId);
}

/// In-memory JWT version store for tests and local development.
class InMemoryAuthJwtVersionStore
    implements AuthJwtVersionStore, AuthInMemoryDeletionState {
  final Map<String, int> _versions = <String, int>{};

  /// Captures the per-user versions for rollback by a deletion transaction.
  @override
  Object captureDeletionState() => Map<String, int>.of(_versions);

  /// Restores a snapshot produced by [captureDeletionState].
  ///
  /// Throws a [TypeError] when [state] is not this store's snapshot shape.
  @override
  void restoreDeletionState(Object state) {
    _versions
      ..clear()
      ..addAll(state as Map<String, int>);
  }

  /// Returns the current version, defaulting to zero for a new user.
  ///
  /// Throws an [ArgumentError] when [userId] is blank after trimming. The
  /// original non-blank ID is used as the map key.
  @override
  Future<int> current(String userId) async {
    _validateUserId(userId);
    return _versions[userId] ?? 0;
  }

  /// Advances and returns the version associated with [userId].
  ///
  /// Throws an [ArgumentError] when [userId] is blank after trimming. Older
  /// JWTs become invalid when their embedded version no longer matches.
  @override
  Future<int> rotate(String userId) async {
    _validateUserId(userId);
    final next = (_versions[userId] ?? 0) + 1;
    _versions[userId] = next;
    return next;
  }

  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }
}
