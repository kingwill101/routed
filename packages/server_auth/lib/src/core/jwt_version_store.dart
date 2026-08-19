import 'dart:async';

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
class InMemoryAuthJwtVersionStore implements AuthJwtVersionStore {
  final Map<String, int> _versions = <String, int>{};

  @override
  Future<int> current(String userId) async {
    _validateUserId(userId);
    return _versions[userId] ?? 0;
  }

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
