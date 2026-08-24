import 'dart:async';

/// Represents an owned cache lock that can optionally expire.
///
/// A lock has an owner identifier so that one lock handle cannot release a
/// lock acquired by another handle. Use [get] or [block] when the protected
/// operation should be released automatically, including when the callback
/// throws.
abstract class Lock {
  /// Attempts to run [callback] while holding the lock.
  ///
  /// If [callback] is omitted, returns `true` when this handle acquires the
  /// lock and `false` otherwise. If [callback] is supplied, the callback is
  /// invoked only after successful acquisition and its result is returned.
  /// The lock is released after the callback completes, including when it
  /// throws. A callback may return either a value or a `Future`.
  FutureOr<dynamic> get([Function? callback]);

  /// Attempts to acquire the lock immediately.
  ///
  /// Returns `true` when this handle becomes the owner and `false` when the
  /// lock is already held by another owner. A successful acquisition starts
  /// the lease configured when this lock was created.
  FutureOr<bool> acquire();

  /// Waits up to [seconds] to acquire the lock, then runs [callback].
  ///
  /// The [seconds] argument is the acquisition timeout, not the lifetime of
  /// the lock. Once acquired, callback and return-value behavior matches
  /// [get]. Throws a `LockTimeoutException` when the lock cannot be acquired
  /// before the timeout expires.
  FutureOr<dynamic> block(int seconds, [Function? callback]);

  /// Releases the lock when this handle is its current owner.
  ///
  /// Returns `true` when the lock was released and `false` when it is owned by
  /// another handle, has already expired, or is no longer present.
  FutureOr<bool> release();

  /// Returns this handle's owner identifier.
  ///
  /// Pass this value to a lock provider's `restoreLock` method when another
  /// part of an application needs to reconstruct a handle for the same owner.
  FutureOr<String> owner();

  /// Returns the owner identifier currently persisted by the backend.
  ///
  /// Returns `null` when the lock is not held or has expired. Unlike [owner],
  /// this method reports the backend's current state rather than this handle's
  /// identity.
  FutureOr<String?> getCurrentOwner();

  /// Whether this handle currently owns the persisted lock.
  ///
  /// This compares the handle's owner identifier with [getCurrentOwner]. It
  /// does not imply that the lock will remain valid for the duration of a
  /// subsequent operation.
  FutureOr<bool> isOwnedByCurrentProcess();

  /// Requests release of the lock regardless of its current owner.
  ///
  /// Use this only for recovery or administrative cleanup. It can interrupt
  /// another owner and cause two operations to run concurrently. Because the
  /// contract returns `void`, implementations cannot report completion or a
  /// backend failure through this method.
  void forceRelease();
}
