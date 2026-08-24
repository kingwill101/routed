import 'dart:async';

import 'package:server_cache/src/array_store.dart';
import 'package:server_cache/src/lock.dart';
import 'package:server_contracts/server_contracts.dart';

/// An isolate-local lock backed by an in-memory [ArrayStore].
///
/// The lock state is lost when the store is discarded and is not shared with
/// other isolates or processes. Use this implementation for tests and
/// single-isolate applications, not for coordinating multiple workers.
class ArrayLock extends CacheLock {
  /// Creates a lock with the given [store], [name], and lease duration.
  ///
  /// [seconds] controls how long a successful acquisition remains valid. A
  /// value of `0` creates a lease without an expiration time. [owner] is an
  /// identifier used for cooperative ownership checks; it is not a security
  /// credential.
  ArrayLock(this.store, String name, int seconds, [String? owner])
    : super(name, seconds, owner);

  /// The underlying array store used for locking.
  final ArrayStore store;

  /// Acquires the lock if it is not already held by another owner.
  ///
  /// Expired entries are replaced lazily when this method is called. Returns
  /// `true` when this isolate records the acquisition and `false` when an
  /// unexpired entry is present.
  @override
  Future<bool> acquire() async {
    final entry = store.locks[super.name] as Map<Object?, Object?>?;
    final expiration = entry?['expiresAt'];
    if (expiration != null &&
        DateTime.now().isBefore(
          DateTime.fromMillisecondsSinceEpoch(expiration as int),
        )) {
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

  /// Releases the lock if its recorded owner matches this lock instance.
  ///
  /// Returns `true` when the entry is removed and `false` when another owner
  /// holds it.
  @override
  Future<bool> release() async {
    if (await isOwnedByCurrentProcess()) {
      forceRelease();
      return true;
    }
    return false;
  }

  /// Gets the recorded owner of the lock.
  ///
  /// Returns `null` when no entry exists. An expired entry may remain visible
  /// until a later lock operation removes it.
  @override
  Future<String?> getCurrentOwner() async {
    final entry = store.locks[super.name] as Map<Object?, Object?>?;
    final owner = entry?['owner'];
    return owner as String?;
  }

  /// Checks whether the recorded owner matches this lock instance.
  ///
  /// Returns `true` if the lock is owned by the current process, `false`
  /// otherwise.
  @override
  Future<bool> isOwnedByCurrentProcess() async {
    return (await getCurrentOwner()) == ownerId;
  }

  /// Removes the lock entry regardless of ownership.
  ///
  /// Call this only when forcibly recovering a stuck lock. It can release a
  /// lock that another isolate or operation has just acquired.
  @override
  void forceRelease() {
    store.locks.remove(super.name);
  }

  /// Polls until the lock is acquired or the timeout is reached.
  ///
  /// If [callback] is provided, it runs while this lock is held and the lock
  /// is released when the callback completes or throws. Throws a
  /// [LockTimeoutException] if the lock cannot be acquired within [seconds].
  /// Polling uses [CacheLock.sleepMilliseconds] between attempts.
  @override
  Future<dynamic> block(int seconds, [Function? callback]) async {
    final starting = DateTime.now().millisecondsSinceEpoch;
    final milliseconds = seconds * 1000;

    while (!await acquire()) {
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now + super.sleepMilliseconds - milliseconds) >= starting) {
        throw LockTimeoutException('Lock timeout');
      }

      await Future<void>.delayed(
        Duration(milliseconds: super.sleepMilliseconds),
      );
    }

    if (callback != null) {
      try {
        return await Function.apply(callback, const <dynamic>[]);
      } finally {
        await release();
      }
    }

    return true;
  }

  /// Acquires the lock and optionally executes a [callback] while holding it.
  ///
  /// Returns the callback result, `true` when the lock was acquired without a
  /// callback, or `false` when the lock was already held. The lock is released
  /// after the callback completes or throws.
  @override
  Future<dynamic> get([Function? callback]) async {
    final result = await acquire();

    if (result && callback != null) {
      try {
        return await Function.apply(callback, const <dynamic>[]);
      } finally {
        await release();
      }
    }

    return result;
  }
}
