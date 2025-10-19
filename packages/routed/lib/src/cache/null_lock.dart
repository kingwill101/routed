import 'package:routed/src/cache/lock.dart';

class NullLock extends CacheLock {
  NullLock(super.name, super.seconds, [super.owner]);

  bool _acquired = false;

  @override
  Future<bool> acquire() async {
    _acquired = true;
    return true;
  }

  @override
  Future<bool> release() async {
    _acquired = false;
    return true;
  }

  @override
  Future<String?> getCurrentOwner() async {
    return _acquired ? ownerId : null;
  }

  @override
  void forceRelease() {
    _acquired = false;
  }
}
