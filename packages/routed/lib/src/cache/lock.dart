import 'dart:async';
import 'dart:math';

import 'package:routed/src/contracts/cache/lock.dart' as lock_contract;
import 'package:routed/src/contracts/cache/lock_timeout_exception.dart';

/// An abstract class representing a lock mechanism.
/// This class implements the [lock_contract.Lock] interface.
abstract class CacheLock implements lock_contract.Lock {
  /// The name of the lock.
  final String name;

  /// The duration in seconds for which the lock will be held.
  final int seconds;

  /// The unique identifier for the owner of the lock.
  final String ownerId;

  /// The duration in milliseconds to sleep between attempts to acquire the lock.
  int sleepMilliseconds = 250;

  /// Constructs a [CacheLock] instance with the given [name] and [seconds].
  /// If [owner] is not provided, a random string is generated as the owner ID.
  CacheLock(this.name, this.seconds, [String? owner])
    : ownerId = owner ?? _generateRandomString();

  /// Acquires the lock.
  ///
  /// Returns `true` if the lock is successfully acquired, otherwise `false`.
  @override
  Future<bool> acquire();

  /// Releases the lock.
  ///
  /// Returns `true` if the lock is successfully released, otherwise `false`.
  @override
  Future<bool> release();

  /// Acquires the lock and executes the given [callback] if provided.
  ///
  /// If the lock is acquired and [callback] is provided, the [callback] is executed.
  /// The lock is released after the [callback] is executed.
  ///
  /// Returns the result of the [callback] if it is executed, otherwise the result of [acquire].
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

  /// Blocks until the lock is acquired or the specified [seconds] timeout is reached.
  ///
  /// If the lock is acquired and [callback] is provided, the [callback] is executed.
  /// The lock is released after the [callback] is executed.
  ///
  /// Throws [LockTimeoutException] if the lock cannot be acquired within the specified [seconds].
  ///
  /// Returns the result of the [callback] if it is executed, otherwise `true`.
  @override
  Future<dynamic> block(int seconds, [Function? callback]) async {
    final starting = DateTime.now().millisecondsSinceEpoch;
    final milliseconds = seconds * 1000;

    while (!await acquire()) {
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now + sleepMilliseconds - milliseconds) >= starting) {
        throw LockTimeoutException('Lock timeout');
      }

      await Future<void>.delayed(Duration(milliseconds: sleepMilliseconds));
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

  /// Returns the owner ID of the lock.
  @override
  owner() {
    return ownerId;
  }

  /// Retrieves the current owner of the lock.
  ///
  /// Returns the owner ID if the lock is currently held, otherwise `null`.
  @override
  Future<String?> getCurrentOwner();

  /// Checks if the lock is owned by the current process.
  ///
  /// Returns `true` if the lock is owned by the current process, otherwise `false`.
  @override
  Future<bool> isOwnedByCurrentProcess() async {
    return (await getCurrentOwner()) == ownerId;
  }

  /// Sets the duration in milliseconds to sleep between attempts to acquire the lock.
  void betweenBlockedAttemptsSleepFor(int milliseconds) {
    sleepMilliseconds = milliseconds;
  }

  /// Generates a random string of the specified [length].
  ///
  /// The default [length] is 16 characters.
  static String _generateRandomString([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }
}
