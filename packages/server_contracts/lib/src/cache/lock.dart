import 'dart:async';

/// Contract for an owned, expiring cache lock.
abstract class Lock {
  /// Executes [callback] while holding the lock, when supported.
  FutureOr<dynamic> get([Function? callback]);

  /// Attempts to acquire the lock.
  FutureOr<bool> acquire();

  /// Waits up to [seconds] for the lock, then executes [callback].
  FutureOr<dynamic> block(int seconds, [Function? callback]);

  /// Releases the lock when owned by the current owner.
  FutureOr<bool> release();

  /// Returns the owner identifier for this lock.
  FutureOr<String> owner();

  /// Returns the currently persisted owner identifier, if any.
  FutureOr<String?> getCurrentOwner();

  /// Whether this process currently owns the lock.
  FutureOr<bool> isOwnedByCurrentProcess();

  /// Releases the lock regardless of its current owner.
  void forceRelease();
}
