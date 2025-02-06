import 'dart:async';

abstract class Lock {
  /// Attempts to acquire the lock.
  ///
  /// If a callback function is provided, it will be executed once the lock is acquired.
  /// The lock will be released after the callback function is executed.
  ///
  /// Returns the result of the callback function if provided, otherwise returns a boolean indicating whether the lock was acquired.
  FutureOr<dynamic> get([Function? callback]);

  /// Attempts to acquire the lock.
  ///
  /// Returns true if the lock was successfully acquired, otherwise false.
  FutureOr<bool> acquire();

  /// Attempts to acquire the lock for the given number of seconds.
  ///
  /// This method will keep trying to acquire the lock for the specified number of seconds.
  /// If a callback function is provided, it will be executed once the lock is acquired.
  /// The lock will be released after the callback function is executed or the timeout is reached.
  ///
  /// Throws a [LockTimeoutException] if the lock cannot be acquired within the specified time.
  ///
  /// Returns the result of the callback function if provided, otherwise returns a boolean indicating whether the lock was acquired.
  FutureOr<dynamic> block(int seconds, [Function? callback]);

  /// Releases the lock.
  ///
  /// Returns true if the lock was successfully released, otherwise false.
  FutureOr<bool> release();

  /// Returns the current owner of the lock.
  ///
  /// Returns the identifier of the current owner of the lock.
  FutureOr<String> owner();

  /// Returns the current owner of the lock.
  ///
  /// Returns the identifier of the current owner of the lock.
  FutureOr<String?> getCurrentOwner();

  /// Determines whether this lock is allowed to release the lock in the driver.
  ///
  /// Returns true if the lock is owned by the current process, otherwise false.
  FutureOr<bool> isOwnedByCurrentProcess();

  /// Forcefully releases the lock regardless of the current owner.
  void forceRelease();
}
