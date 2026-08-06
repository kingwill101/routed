import 'dart:async';

abstract class Store {
  FutureOr<dynamic> get(String key);

  FutureOr<Map<String, dynamic>> many(List<String> keys);

  FutureOr<bool> put(String key, dynamic value, int seconds);

  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds);

  FutureOr<dynamic> increment(String key, [int value = 1]);

  FutureOr<dynamic> decrement(String key, [int value = 1]);

  FutureOr<bool> forever(String key, dynamic value);

  FutureOr<bool> forget(String key);

  FutureOr<bool> flush();

  String getPrefix();

  FutureOr<List<String>> getAllKeys();
}
