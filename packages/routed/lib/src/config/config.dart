import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/utils/deep_merge.dart';
import 'package:routed/src/utils/dot.dart';

class ConfigImpl implements Config {
  final Map<String, dynamic> _items = <String, dynamic>{};

  ConfigImpl([Map<String, dynamic>? items]) {
    if (items != null) {
      merge(items);
    }
  }

  @override
  bool has(String key) {
    return dot.contains(_items, key);
  }

  @override
  dynamic get(String key, [dynamic defaultValue]) {
    final lookup = dot.lookup(_items, key);
    if (lookup.exists) {
      return lookup.value;
    }
    return defaultValue;
  }

  @override
  T getOrThrow<T>(String key, {String? message}) {
    final lookup = dot.lookup(_items, key);
    if (!lookup.exists) {
      throw StateError(message ?? 'Configuration key "$key" is missing');
    }
    return lookup.value as T;
  }

  @override
  Map<String, dynamic> all() {
    return _items;
  }

  @override
  void set(String key, dynamic value) {
    dot.set(_items, key, value);
  }

  @override
  void prepend(String key, dynamic value) {
    final list = _ensureList(key);
    list.insert(0, value);
  }

  @override
  void push(String key, dynamic value) {
    final list = _ensureList(key);
    list.add(value);
  }

  @override
  void merge(Map<String, dynamic> values) {
    deepMerge(_items, values, override: true);
  }

  @override
  void mergeDefaults(Map<String, dynamic> values) {
    deepMerge(_items, values, override: false);
  }

  List<dynamic> _ensureList(String key) {
    final lookup = dot.lookup(_items, key);
    if (lookup.exists && lookup.value is List<dynamic>) {
      return lookup.value as List<dynamic>;
    }
    final list = <dynamic>[];
    dot.set(_items, key, list);
    return list;
  }
}
