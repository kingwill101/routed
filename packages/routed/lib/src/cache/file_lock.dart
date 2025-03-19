import 'package:routed/src/contracts/cache/lock.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/contracts/cache/lock_timeout_exception.dart';

/// {@template FileLock}
/// A lock implementation using files to prevent concurrent execution.
///
/// This class provides a way to synchronize access to resources between
/// different processes. It uses the file system to create and manage locks.
///
/// **Note**: This implementation relies on file system operations for locking,
/// which may have performance implications depending on the underlying storage.
/// {@endtemplate}
class FileLock implements Lock {
  /// The underlying [FileStore] used to manage the lock file.
  final FileStore store;

  /// The name of the lock.
  final String name;

  /// The duration for which the lock is valid, in seconds.
  final int seconds;

  /// An identifier for the lock owner, used to ensure only the owner can release the lock.
  final String? lockOwner;

  /// {@macro FileLock}
  FileLock(this.store, this.name, this.seconds, [this.lockOwner]);

  /// Attempts to acquire the lock by creating a lock file.
  ///
  /// If the lock file already exists, it means the lock is held by another
  /// process, and this method returns `false`. If the lock file is successfully
  /// created, this method returns `true`.
  @override
  Future<bool> acquire() async {
    return store.put(name, lockOwner, seconds);
  }

  /// Releases the lock by deleting the lock file, but only if this instance owns the lock.
  ///
  /// This method first checks if the current process owns the lock before
  /// attempting to release it. This prevents one process from accidentally
  /// releasing a lock held by another process.
  @override
  Future<bool> release() async {
    if (await isOwnedByCurrentProcess()) {
      return store.forget(name);
    }
    return false;
  }

  /// Retrieves the identifier of the current lock owner.
  ///
  /// This method reads the contents of the lock file, which should contain
  /// the identifier of the process that currently holds the lock.
  @override
  Future<String?> getCurrentOwner() async {
    return store.get(name);
  }

  /// Forces the release of the lock, regardless of ownership.
  ///
  /// This method should be used with caution, as it can lead to race conditions
  /// if another process is in the middle of acquiring the lock.
  @override
  void forceRelease() {
    store.forget(name);
  }

  /// Executes a callback while holding the lock, ensuring the lock is released afterwards.
  ///
  /// This method first attempts to acquire the lock, then executes the provided
  /// [callback] if the lock is successfully acquired. The lock is guaranteed to
  /// be released after the callback completes, even if the callback throws an
  /// exception.
  ///
  /// If the lock cannot be acquired, the callback is not executed, and this
  /// method returns `false`.
  @override
  Future<dynamic> get([Function? callback]) async {
    if (await acquire()) {
      try {
        if (callback != null) {
          return await callback();
        }
        return true;
      } finally {
        await release();
      }
    }
    return false;
  }

  /// Blocks execution until the lock can be acquired, or the timeout is reached.
  ///
  /// This method repeatedly attempts to acquire the lock until it succeeds, or
  /// the specified [seconds] have elapsed. If a [callback] is provided, it is
  /// executed once the lock is acquired, and the lock is released after the
  /// callback completes.
  ///
  /// If the lock cannot be acquired within the specified time, a
  /// [LockTimeoutException] is thrown.
  @override
  Future<dynamic> block(int seconds, [Function? callback]) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      if (await acquire()) {
        try {
          if (callback != null) {
            return await callback();
          }
          return true;
        } finally {
          await release();
        }
      }
      await Future.delayed(Duration(milliseconds: 100));
    }
    throw LockTimeoutException(
        'Could not acquire lock within $seconds seconds');
  }

  /// Returns the current owner of the lock.
  ///
  /// If no owner is set `''` is returned.
  @override
  Future<String> owner() async {
    return store.get(name) ?? '';
  }

  /// Checks if the current process owns the lock.
  ///
  /// This method compares the identifier of the current process with the
  /// identifier stored in the lock file. If they match, it means the current
  /// process owns the lock.
  @override
  Future<bool> isOwnedByCurrentProcess() async {
    return store.get(name) == lockOwner;
  }
}
