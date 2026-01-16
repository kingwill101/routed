import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/utils/deep_copy.dart';
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
  T? get<T>(String key, [T? defaultValue]) {
    final lookup = dot.lookup(_items, key);
    if (lookup.exists) {
      if (lookup.value is! T) {
        throw StateError(
          'Configuration key "$key" is not of type ${T.toString()}, got ${lookup.value.runtimeType}',
        );
      }
      return lookup.value as T;
    }
    return defaultValue;
  }

  @override
  T getOrThrow<T>(String key, {String? message}) {
    final lookup = dot.lookup(_items, key);
    if (!lookup.exists) {
      throw StateError(message ?? 'Configuration key "$key" is missing');
    }

    if (lookup.value is! T) {
      throw StateError(
        'Configuration key "$key" is not of type ${T.toString()}, got ${lookup.value.runtimeType}',
      );
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
    final stored = dot.lookup(_items, key);
    if (stored.exists && stored.value is List<dynamic>) {
      return stored.value as List<dynamic>;
    }
    return list;
  }
}

/// A request-scoped config wrapper that overlays mutable values on top of
/// a shared parent config without cloning the full tree.
class ScopedConfig implements Config {
  ScopedConfig(this._parent);

  final Config _parent;
  final Map<String, dynamic> _overrides = <String, dynamic>{};

  @override
  bool has(String key) {
    return dot.contains(_overrides, key) || _parent.has(key);
  }

  @override
  T? get<T>(String key, [T? defaultValue]) {
    final overrideLookup = dot.lookup(_overrides, key);
    if (overrideLookup.exists) {
      final overrideValue = overrideLookup.value;
      if (overrideValue is Map && _parent.has(key)) {
        final parentValue = _parent.get<Object?>(key);
        if (parentValue is Map) {
          final merged = _mergeMaps(parentValue, overrideValue);
          return _castOrThrow<T>(merged);
        }
      }
      return _castOrThrow<T>(overrideValue);
    }
    return _parent.get<T>(key, defaultValue);
  }

  @override
  T getOrThrow<T>(String key, {String? message}) {
    final overrideLookup = dot.lookup(_overrides, key);
    if (overrideLookup.exists) {
      final overrideValue = overrideLookup.value;
      if (overrideValue is Map && _parent.has(key)) {
        final parentValue = _parent.get<Object?>(key);
        if (parentValue is Map) {
          final merged = _mergeMaps(parentValue, overrideValue);
          return _castOrThrow<T>(merged, message: message);
        }
      }
      return _castOrThrow<T>(overrideValue, message: message);
    }
    return _parent.getOrThrow<T>(key, message: message);
  }

  @override
  Map<String, dynamic> all() {
    final merged = deepCopyMap(_parent.all());
    if (_overrides.isNotEmpty) {
      deepMerge(merged, _overrides, override: true);
    }
    return merged;
  }

  @override
  void set(String key, dynamic value) {
    dot.set(_overrides, key, value);
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
    deepMerge(_overrides, values, override: true);
  }

  @override
  void mergeDefaults(Map<String, dynamic> values) {
    if (values.isEmpty) {
      return;
    }
    final missing = _collectMissing(values, '');
    if (missing.isNotEmpty) {
      deepMerge(_overrides, missing, override: true);
    }
  }

  List<dynamic> _ensureList(String key) {
    final overrideLookup = dot.lookup(_overrides, key);
    if (overrideLookup.exists && overrideLookup.value is List<dynamic>) {
      return overrideLookup.value as List<dynamic>;
    }
    if (_parent.has(key)) {
      final parentValue = _parent.get<Object?>(key);
      if (parentValue is List) {
        final copy = deepCopyList(parentValue);
        dot.set(_overrides, key, copy);
        return copy;
      }
    }
    final list = <dynamic>[];
    dot.set(_overrides, key, list);
    return list;
  }

  Map<String, dynamic> _collectMissing(
    Map<String, dynamic> values,
    String prefix,
  ) {
    final result = <String, dynamic>{};
    values.forEach((key, value) {
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      final existing = _lookupValue(fullKey);
      if (value is Map) {
        if (existing == null) {
          dot.set(result, fullKey, value);
        } else if (existing is Map) {
          final child = _collectMissing(_stringKeyedMap(value), fullKey);
          if (child.isNotEmpty) {
            deepMerge(result, child, override: true);
          }
        }
      } else {
        if (existing == null) {
          dot.set(result, fullKey, value);
        }
      }
    });
    return result;
  }

  Object? _lookupValue(String key) {
    final overrideLookup = dot.lookup(_overrides, key);
    if (overrideLookup.exists) {
      return overrideLookup.value;
    }
    if (_parent.has(key)) {
      return _parent.get<Object?>(key);
    }
    return null;
  }

  Map<String, dynamic> _mergeMaps(Map left, Map right) {
    final merged = _stringKeyedMap(left);
    deepMerge(merged, _stringKeyedMap(right), override: true);
    return merged;
  }

  Map<String, dynamic> _stringKeyedMap(Map value) {
    final mapped = <String, dynamic>{};
    value.forEach((key, dynamic v) {
      mapped[key is String ? key : key.toString()] = v;
    });
    return mapped;
  }

  T _castOrThrow<T>(Object? value, {String? message}) {
    if (value is! T) {
      throw StateError(
        message ??
            'Configuration key is not of type ${T.toString()}, got ${value.runtimeType}',
      );
    }
    return value as T;
  }
}
