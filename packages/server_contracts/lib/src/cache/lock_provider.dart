import 'dart:async';

import 'package:server_contracts/src/cache/lock.dart';

/// Creates and restores locks for a cache backend.
abstract class LockProvider {
  /// Creates a lock named [name] with an optional lifetime and [owner].
  FutureOr<Lock> lock(String name, [int seconds = 0, String? owner]);

  /// Restores a lock named [name] for an existing [owner].
  FutureOr<Lock> restoreLock(String name, String owner);
}
