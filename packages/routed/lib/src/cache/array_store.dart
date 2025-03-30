import 'dart:async';
import 'dart:convert';

import 'package:routed/src/cache/array_lock.dart';
import 'package:routed/src/cache/taggable_store.dart';
import 'package:routed/src/contracts/cache/lock.dart';
import 'package:routed/src/contracts/cache/lock_provider.dart';
import 'package:routed/src/contracts/cache/store.dart';

/// A store that uses an in-memory array to store cache data.
class ArrayStore extends TaggableStore implements Store, LockProvider {
  /// A map to store the cache data.
  final Map<String, dynamic> storage = {};

  /// A map to store the locks.
  final Map<String, dynamic> locks = {};

  /// Whether to serialize values before storing them.
  final bool serializesValues;

  /// Creates an [ArrayStore] instance.
  ///
  /// If [serializesValues] is true, values will be serialized before storing.
  ArrayStore([this.serializesValues = false]);

  /// Retrieves all keys from the store.
  ///
  /// Returns a list of all keys.
  @override
  Future<List<String>> getAllKeys() async {
    return storage.keys.toList();
  }

  /// Retrieves an item from the store by [key].
  ///
  /// Returns the item if found, or null if not found or expired.
  @override
  Future<dynamic> get(String key) async {
    if (!storage.containsKey(key)) {
      return null;
    }
      final item = storage[key];
      if (item == null) {
        return null;
      }

      final num? expiresAt = item['expiresAt'] as num?;
      if (expiresAt != null &&
          expiresAt != 0 &&
          (DateTime.now().millisecondsSinceEpoch / 1000) >= expiresAt) {
        await forget(key);
        return null;
      }

      final value = item['value'];
      if (value == null) {
        return null;
      }

      return serializesValues ? _deserialize(value as String) : value;
    }

  /// Stores an item in the store with a time-to-live of [seconds].
  ///
  /// Returns true if the item was successfully stored.
  @override
  Future<bool> put(String key, dynamic value, int seconds) async {
    storage[key] = {
      'value': serializesValues ? _serialize(value) : value,
      'expiresAt': _calculateExpiration(seconds),
    };
    return true;
  }

  /// Stores multiple items in the store with a time-to-live of [seconds].
  ///
  /// Returns true if all items were successfully stored.
  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    for (var entry in values.entries) {
      await put(entry.key, entry.value, seconds);
    }
    return true;
  }

  /// Increments the value of an item in the store by [value].
  ///
  /// Returns the new value.
  @override
  Future<dynamic> increment(String key, [int value = 1]) async {
    final item = storage[key];
    final currentValue = item?['value'] ?? 0;
    final newValue = (currentValue is int
            ? currentValue
            : int.parse(currentValue.toString())) +
        value;
    final num? expiresAt = item?['expiresAt'] as num?;
    final int remainingTime = expiresAt == null || expiresAt == 0
        ? 0
        : ((expiresAt - DateTime.now().millisecondsSinceEpoch / 1000).round());
    await put(key, newValue, remainingTime);
    return newValue;
  }

  /// Decrements the value of an item in the store by [value].
  ///
  /// Returns the new value.
  @override
  Future<dynamic> decrement(String key, [int value = 1]) async {
    return increment(key, -value);
  }

  /// Stores an item in the store indefinitely.
  ///
  /// Returns true if the item was successfully stored.
  @override
  Future<bool> forever(String key, dynamic value) async {
    return put(key, value, 0);
  }

  /// Removes an item from the store by [key].
  ///
  /// Returns true if the item was successfully removed.
  @override
  Future<bool> forget(String key) async {
    storage.remove(key);
    return true;
  }

  /// Clears all items from the store.
  ///
  /// Returns true if the store was successfully cleared.
  @override
  Future<bool> flush() async {
    storage.clear();
    return true;
  }

  /// Gets the prefix for the store.
  ///
  /// Returns an empty string.
  @override
  String getPrefix() {
    return '';
  }

  /// Acquires a lock with the given [name].
  ///
  /// Returns a [Lock] instance.
  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async {
    return ArrayLock(this, name, seconds, owner);
  }

  /// Restores a lock with the given [name] and [owner].
  ///
  /// Returns a [Lock] instance.
  @override
  Future<Lock> restoreLock(String name, String owner) async {
    return lock(name, 0, owner);
  }

  /// Calculates the expiration timestamp for a given duration in [seconds].
  double _calculateExpiration(int seconds) {
    return _toTimestamp(seconds);
  }

  /// Converts a duration in [seconds] to a timestamp.
  double _toTimestamp(int seconds) {
    return seconds > 0
        ? (DateTime.now().millisecondsSinceEpoch / 1000) + seconds
        : 0;
  }

  /// Serializes a value to a JSON string.
  String _serialize(dynamic value) {
    return jsonEncode(value);
  }

  /// Deserializes a JSON string to a value.
  dynamic _deserialize(String value) {
    return jsonDecode(value);
  }

  /// Retrieves multiple items from the store by their [keys].
  ///
  /// Returns a map of key-value pairs.
  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    final Map<String, dynamic> results = {};
    for (var key in keys) {
      results[key] = await get(key);
    }
    return results;
  }
}
