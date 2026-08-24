import 'dart:async';
import 'dart:math';

import 'package:server_contracts/server_contracts.dart' as lock_contract;
import 'package:server_contracts/server_contracts.dart';

/// Shared lock behavior for cache-backed lock implementations.
///
/// The lock contract is cooperative: [ownerId] identifies the caller but is
/// not a cryptographic credential. Concrete stores decide whether ownership
/// and acquisition are atomic across isolates or processes.
abstract class CacheLock implements lock_contract.Lock {
  /// Creates a lock named [name] with a lease of [seconds].
  ///
  /// A non-positive lease is interpreted by each backend according to its
  /// store contract. If [owner] is omitted, a per-instance owner identifier is
  /// generated. The generated identifier is for coordination only, not
  /// authentication.
  CacheLock(this.name, this.seconds, [String? owner])
    : ownerId = owner ?? _generateRandomString();

  /// The backend key or name used to identify the lock.
  final String name;

  /// The requested lease duration in seconds.
  final int seconds;

  /// The cooperative owner identifier used for release checks.
  final String ownerId;

  /// The delay in milliseconds between [block] acquisition attempts.
  ///
  /// This is mutable so callers can tune polling for a backend, but a very
  /// small value can create unnecessary load.
  int sleepMilliseconds = 250;

  /// Attempts to acquire the lock.
  ///
  /// Returns `true` if the lock is successfully acquired, otherwise `false`.
  @override
  Future<bool> acquire();

  /// Releases the lock when the backend recognizes this owner.
  ///
  /// Returns `true` if the lock is successfully released, otherwise `false`.
  @override
  Future<bool> release();

  /// Acquires the lock and optionally executes [callback] while holding it.
  ///
  /// The lock is released when [callback] completes or throws. Returns the
  /// callback result, or the acquisition result when no callback is supplied.
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

  /// Polls until the lock is acquired or the [seconds] timeout is reached.
  ///
  /// If [callback] is supplied, it runs while the lock is held and the lock is
  /// released when it completes or throws. Throws [LockTimeoutException] if
  /// acquisition does not succeed before the timeout. Returns the callback
  /// result, or `true` when no callback is supplied.
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
        return await Function.apply(callback, const <dynamic>[]);
      } finally {
        await release();
      }
    }

    return true;
  }

  /// Returns this lock instance's owner identifier.
  @override
  String owner() {
    return ownerId;
  }

  /// Retrieves the owner identifier recorded by the backend.
  ///
  /// Returns the owner ID if the lock is currently held, otherwise `null`.
  @override
  Future<String?> getCurrentOwner();

  /// Checks whether the backend owner matches [ownerId].
  ///
  /// Returns `true` if the lock is owned by the current process, otherwise
  /// `false`.
  @override
  Future<bool> isOwnedByCurrentProcess() async {
    return (await getCurrentOwner()) == ownerId;
  }

  /// Sets the delay between blocked acquisition attempts.
  ///
  /// The value is used by [block] and is measured in milliseconds.
  // The method form is part of the public cache-lock API and is retained for
  // source compatibility with existing callers.
  // ignore: use_setters_to_change_properties
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
