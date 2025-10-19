import 'package:routed/src/cache/null_lock.dart';
import 'package:routed/src/cache/taggable_store.dart';
import 'package:routed/src/contracts/cache/lock.dart';
import 'package:routed/src/contracts/cache/lock_provider.dart';
import 'package:routed/src/contracts/cache/store.dart';

class NullStore extends TaggableStore implements Store, LockProvider {
  @override
  Future<List<String>> getAllKeys() async => const <String>[];

  @override
  Future<dynamic> get(String key) async => null;

  @override
  Future<bool> put(String key, value, int seconds) async => true;

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async => true;

  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async =>
      value is num ? value : 1;

  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async =>
      value is num ? -value : -1;

  @override
  Future<bool> forever(String key, value) async => true;

  @override
  Future<bool> forget(String key) async => true;

  @override
  Future<bool> flush() async => true;

  @override
  String getPrefix() => '';

  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async =>
      NullLock(name, seconds, owner);

  @override
  Future<Lock> restoreLock(String name, String owner) async =>
      NullLock(name, 0, owner)..acquire();

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async =>
      <String, dynamic>{};
}
