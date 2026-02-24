import 'dart:async';

abstract class Lock {
  FutureOr<dynamic> get([Function? callback]);

  FutureOr<bool> acquire();

  FutureOr<dynamic> block(int seconds, [Function? callback]);

  FutureOr<bool> release();

  FutureOr<String> owner();

  FutureOr<String?> getCurrentOwner();

  FutureOr<bool> isOwnedByCurrentProcess();

  void forceRelease();
}
