import 'dart:async';

import 'lock.dart';

abstract class LockProvider {
  FutureOr<Lock> lock(String name, [int seconds = 0, String? owner]);

  FutureOr<Lock> restoreLock(String name, String owner);
}
