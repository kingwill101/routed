import 'dart:async';

import 'lock.dart';

abstract class LockProvider {
  /// Returns a lock instance.
  ///
  /// [name] is the name of the lock.
  /// [seconds] is the number of seconds the lock should be maintained.
  /// [owner] is the scope identifier of this lock.
  FutureOr<Lock> lock(String name, [int seconds = 0, String? owner]);

  /// Restores a lock instance using the owner identifier.
  ///
  /// [name] is the name of the lock.
  /// [owner] is the scope identifier of this lock.
  FutureOr<Lock> restoreLock(String name, String owner);
}
