import 'dart:async';

import 'package:routed/src/contracts/cache/lock_timeout_exception.dart';

import 'array_store.dart';
import 'lock.dart';

/// A lock implementation using an in-memory array store.
class ArrayLock extends Lock {
  /// The underlying array store used for locking.
  final ArrayStore store;

  /// Creates an [ArrayLock] with the given [store], [name], [seconds], and optional [owner].
  ArrayLock(this.store, String name, int seconds, [String? owner])
      : super(name, seconds, owner);

  /// Acquires the lock if it is not already held by another process.
  ///
  /// Returns `true` if the lock was successfully acquired, `false` otherwise.
  @override
  Future<bool> acquire() async {
    final expiration = store.locks[super.name]?['expiresAt'];
    if (expiration != null &&
        DateTime.now()
            .isBefore(DateTime.fromMillisecondsSinceEpoch(expiration as int))) {
      return false;
    }

    store.locks[super.name] = {
      'owner': super.ownerId,
      'expiresAt': super.seconds == 0
          ? null
          : DateTime.now()
              .add(Duration(seconds: super.seconds))
              .millisecondsSinceEpoch,
    };
    return true;
  }

  /// Releases the lock if it is owned by the current process.
  ///
  /// Returns `true` if the lock was successfully released, `false` otherwise.
  @override
  Future<bool> release() async {
    if (await isOwnedByCurrentProcess()) {
      forceRelease();
      return true;
    }
    return false;
  }

  /// Gets the current owner of the lock.
  ///
  /// Returns the owner ID if the lock is held, `null` otherwise.
  @override
  Future<String?> getCurrentOwner() async {
    final dynamic owner = store.locks[super.name]?['owner'];
    return owner as String?;
  }

  /// Checks if the lock is owned by the current process.
  ///
  /// Returns `true` if the lock is owned by the current process, `false` otherwise.
  @override
  Future<bool> isOwnedByCurrentProcess() async {
    return (await getCurrentOwner()) == ownerId;
  }

  /// Forces the release of the lock, regardless of ownership.
  @override
  void forceRelease() {
    store.locks.remove(super.name);
  }

  /// Blocks until the lock is acquired or the timeout is reached.
  ///
  /// If a [callback] is provided, it is executed once the lock is acquired.
  /// Throws a [LockTimeoutException] if the lock could not be acquired within the specified [seconds].
  @override
  Future<dynamic> block(int seconds, [Function? callback]) async {
    final starting = DateTime.now().millisecondsSinceEpoch;
    final milliseconds = seconds * 1000;

    while (!await acquire()) {
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now + super.sleepMilliseconds - milliseconds) >= starting) {
        throw LockTimeoutException('Lock timeout');
      }

      await Future<void>.delayed(Duration(milliseconds: super.sleepMilliseconds));
    }

    if (callback != null) {
      try {
        return await callback();
      } finally {
        await release();
      }
    }

    return true;
  }

  /// Acquires the lock and optionally executes a [callback].
  ///
  /// If the lock is acquired and a [callback] is provided, the callback is executed.
  /// Returns the result of the callback or `true` if no callback is provided.
  @override
  Future<dynamic> get([Function? callback]) async {
    final result = await acquire();

    if (result && callback != null) {
      try {
        return await callback();
      } finally {
        await release();
      }
    }

    return result;
  }
}
