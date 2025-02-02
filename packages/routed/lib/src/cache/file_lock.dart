import 'package:routed/src/contracts/cache/lock.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/contracts/cache/lock_timeout_exception.dart';

class FileLock implements Lock {
  final FileStore store;
  final String name;
  final int seconds;
  final String? lockOwner;

  FileLock(this.store, this.name, this.seconds, [this.lockOwner]);

  @override
  Future<bool> acquire() async {
    return store.put(name, lockOwner, seconds);
  }

  @override
  Future<bool> release() async {
    if (await isOwnedByCurrentProcess()) {
      return store.forget(name);
    }
    return false;
  }

  @override
  Future<String?> getCurrentOwner() async {
    return store.get(name);
  }

  @override
  void forceRelease() {
    store.forget(name);
  }

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

  @override
  Future<String> owner() async {
    return store.get(name) ?? '';
  }

  @override
  Future<bool> isOwnedByCurrentProcess() async {
    return store.get(name) == lockOwner;
  }
}
