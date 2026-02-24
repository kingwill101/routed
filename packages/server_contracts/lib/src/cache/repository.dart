import 'dart:async';

import 'store.dart';

abstract class Repository {
  FutureOr<dynamic> pull(dynamic key, [dynamic defaultValue]);

  FutureOr<dynamic> get(String key);

  FutureOr<bool> put(String key, dynamic value, [Duration? ttl]);

  FutureOr<bool> add(String key, dynamic value, [Duration? ttl]);

  FutureOr<dynamic> increment(String key, [dynamic value = 1]);

  FutureOr<dynamic> decrement(String key, [dynamic value = 1]);

  FutureOr<bool> forever(String key, dynamic value);

  FutureOr<dynamic> remember(String key, dynamic ttl, Function callback);

  FutureOr<dynamic> sear(String key, Function callback);

  FutureOr<dynamic> rememberForever(String key, Function callback);

  FutureOr<bool> forget(String key);

  Store getStore();
}
