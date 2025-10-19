import 'package:routed/src/contracts/contracts.dart';

class ConfigImpl implements Config {
  final Map<String, dynamic> _items = <String, dynamic>{};

  ConfigImpl([Map<String, dynamic>? items]) {
    if (items != null) {
      merge(items);
    }
  }

  @override
  bool has(String key) {
    return _lookup(key).exists;
  }

  @override
  dynamic get(String key, [dynamic defaultValue]) {
    final lookup = _lookup(key);
    if (lookup.exists) {
      return lookup.value;
    }
    return defaultValue;
  }

  @override
  T getOrThrow<T>(String key, {String? message}) {
    final lookup = _lookup(key);
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
    final segments = _segments(key);
    final parent = _ensureParent(segments);
    parent[segments.last] = value;
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
    _mergeMap(_items, values, override: true);
  }

  @override
  void mergeDefaults(Map<String, dynamic> values) {
    _mergeMap(_items, values, override: false);
  }

  _LookupResult _lookup(String key) {
    final segments = _segments(key);
    if (segments.isEmpty) {
      return _LookupResult(_items, true, _items);
    }
    Map<String, dynamic>? current = _items;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      final next = current?[segment];
      if (next is Map<String, dynamic>) {
        current = next;
      } else {
        return const _LookupResult(null, false, null);
      }
    }
    final last = segments.last;
    if (current == null) {
      return const _LookupResult(null, false, null);
    }
    if (!current.containsKey(last)) {
      return _LookupResult(current, false, null);
    }
    return _LookupResult(current, true, current[last]);
  }

  Map<String, dynamic> _ensureParent(List<String> segments) {
    Map<String, dynamic> current = _items;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      final next = current[segment];
      if (next is Map<String, dynamic>) {
        current = next;
        continue;
      }
      final newMap = <String, dynamic>{};
      current[segment] = newMap;
      current = newMap;
    }
    return current;
  }

  List<dynamic> _ensureList(String key) {
    final segments = _segments(key);
    final parent = _ensureParent(segments);
    final existing = parent[segments.last];
    if (existing is List<dynamic>) {
      return existing;
    }
    final list = <dynamic>[];
    parent[segments.last] = list;
    return list;
  }

  void _mergeMap(
    Map<String, dynamic> target,
    Map<String, dynamic> source, {
    required bool override,
  }) {
    source.forEach((key, value) {
      if (key.contains('.')) {
        if (value is Map<String, dynamic>) {
          value.forEach((nestedKey, nestedValue) {
            final compoundKey = '$key.$nestedKey';
            if (override) {
              merge({compoundKey: nestedValue});
            } else {
              mergeDefaults({compoundKey: nestedValue});
            }
          });
        } else if (value is List) {
          final exists = _lookup(key).exists;
          if (override || !exists) {
            set(key, List<dynamic>.from(value));
          }
        } else {
          final exists = _lookup(key).exists;
          if (override || !exists) {
            set(key, value);
          }
        }
        return;
      }
      if (value is Map<String, dynamic>) {
        final next = target[key];
        if (next is Map<String, dynamic>) {
          _mergeMap(next, value, override: override);
        } else if (override || next == null) {
          final newMap = <String, dynamic>{};
          _mergeMap(newMap, value, override: override);
          if (override || !target.containsKey(key)) {
            target[key] = newMap;
          }
        }
      } else if (value is List) {
        if (override || !target.containsKey(key)) {
          target[key] = List<dynamic>.from(value);
        }
      } else {
        if (override || !target.containsKey(key)) {
          target[key] = value;
        }
      }
    });
  }

  List<String> _segments(String key) {
    return key.split('.').where((segment) => segment.isNotEmpty).toList();
  }
}

class _LookupResult {
  final Map<String, dynamic>? parent;
  final bool exists;
  final dynamic value;

  const _LookupResult(this.parent, this.exists, this.value);
}
