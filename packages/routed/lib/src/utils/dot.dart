/// A utility for interacting with dotted configuration paths.
///
/// Use the top-level constant [dot] for stateless access (`dot.get(...)`,
/// `dot.set(...)`) or create a scoped instance via `dot(map)` /
/// `DotContext(map)` to perform repeated operations against the same map.
const Dot dot = Dot._internal();

class Dot {
  const Dot._internal();

  /// Returns a context bound to [root] for repeated dot operations.
  DotContext call(Map<String, dynamic> root) => DotContext(root);

  /// Reads a value from [source] using a dotted [path].
  ///
  /// Returns `null` when the path cannot be resolved.
  Object? get(Map<String, dynamic> source, String path) {
    final segments = _segments(path);
    if (segments.isEmpty) {
      return source;
    }
    dynamic current = source;
    for (final segment in segments) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
        continue;
      }
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
        continue;
      }
      return null;
    }
    return current;
  }

  /// Returns `true` when [path] resolves to an existing key.
  bool contains(Map<String, dynamic> source, String path) {
    return lookup(source, path).exists;
  }

  /// Performs a lookup that exposes parent metadata (used for write helpers).
  DotLookupResult lookup(Map<String, dynamic> source, String path) {
    final segments = _segments(path);
    if (segments.isEmpty) {
      return DotLookupResult(
        exists: true,
        parent: null,
        key: null,
        value: source,
      );
    }
    dynamic current = source;
    Map<String, dynamic>? parent;
    String? currentKey;
    for (final segment in segments) {
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(segment)) {
          return DotLookupResult(
            exists: false,
            parent: current,
            key: segment,
            value: null,
          );
        }
        parent = current;
        current = current[segment];
        currentKey = segment;
        continue;
      }
      if (current is Map) {
        final normalized = _normalizeMap(current);
        current
          ..clear()
          ..addAll(normalized);
        final coerced = current.cast<String, dynamic>();
        if (!coerced.containsKey(segment)) {
          return DotLookupResult(
            exists: false,
            parent: coerced,
            key: segment,
            value: null,
          );
        }
        parent = coerced;
        current = coerced[segment];
        currentKey = segment;
        continue;
      }
      return DotLookupResult(
        exists: false,
        parent: null,
        key: segment,
        value: null,
      );
    }
    return DotLookupResult(
      exists: true,
      parent: parent,
      key: currentKey,
      value: current,
    );
  }

  /// Writes [value] into [target] using dotted [path].
  ///
  /// Intermediate maps are created as necessary. When both the incoming
  /// [value] and the existing destination are maps, entries are merged
  /// recursively to preserve earlier contributions.
  void set(Map<String, dynamic> target, String path, Object? value) {
    final segments = _segments(path);
    if (segments.isEmpty) {
      return;
    }
    Map<String, dynamic> current = target;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      if (isLast) {
        _writeValue(current, segment, value);
        return;
      }
      final next = current[segment];
      if (next is Map<String, dynamic>) {
        current = next;
        continue;
      }
      if (next is Map) {
        final normalized = _normalizeMap(next);
        next
          ..clear()
          ..addAll(normalized);
        current = next.cast<String, dynamic>();
        continue;
      }
      final created = <String, dynamic>{};
      current[segment] = created;
      current = created;
    }
  }
}

/// Contextual wrapper returned by [Dot.call] allowing chained operations,
/// e.g. `dot(map).get('a.b')`.
class DotContext {
  DotContext(this._root);

  final Map<String, dynamic> _root;

  Object? get(String path) => dot.get(_root, path);

  void set(String path, Object? value) => dot.set(_root, path, value);

  bool contains(String path) => dot.contains(_root, path);

  DotLookupResult lookup(String path) => dot.lookup(_root, path);
}

List<String> _segments(String path) => path
    .split('.')
    .map((segment) => segment.trim())
    .where((segment) => segment.isNotEmpty)
    .toList(growable: false);

void _writeValue(Map<String, dynamic> target, String key, Object? value) {
  if (value is Map<String, dynamic>) {
    final normalized = _normalizeMap(value);
    final existing = target[key];
    if (existing is Map<String, dynamic>) {
      _merge(existing, normalized);
    } else if (existing is Map) {
      final coerced = _normalizeMap(existing);
      _merge(coerced, normalized);
      target[key] = coerced;
    } else {
      target[key] = normalized;
    }
    return;
  }
  if (value is Map) {
    final incoming = _normalizeMap(value);
    final existing = target[key];
    if (existing is Map<String, dynamic>) {
      _merge(existing, incoming);
    } else if (existing is Map) {
      final coerced = _normalizeMap(existing);
      _merge(coerced, incoming);
      target[key] = coerced;
    } else {
      target[key] = incoming;
    }
    return;
  }
  if (value is Iterable) {
    target[key] = value.map(_normalizeValue).toList();
    return;
  }
  target[key] = value;
}

void _merge(Map<String, dynamic> target, Map<String, dynamic> source) {
  source.forEach((key, value) {
    if (value is Map<String, dynamic>) {
      final normalized = _normalizeMap(value);
      final next = target[key];
      if (next is Map<String, dynamic>) {
        _merge(next, normalized);
      } else if (next is Map) {
        final coerced = _normalizeMap(next);
        _merge(coerced, normalized);
        target[key] = coerced;
      } else {
        target[key] = normalized;
      }
      return;
    }
    if (value is Map) {
      _writeValue(target, key, _normalizeMap(value));
      return;
    }
    if (value is Iterable) {
      target[key] = value.map(_normalizeValue).toList();
      return;
    }
    target[key] = value;
  });
}

Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> value) {
  final result = <String, dynamic>{};
  value.forEach((key, dynamic entry) {
    if (key == null) return;
    result[key.toString()] = _normalizeValue(entry);
  });
  return result;
}

dynamic _normalizeValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return _normalizeMap(value);
  }
  if (value is Map) {
    return _normalizeMap(value);
  }
  if (value is Iterable) {
    return value.map(_normalizeValue).toList();
  }
  return value;
}

class DotLookupResult {
  const DotLookupResult({
    required this.exists,
    required this.parent,
    required this.key,
    required this.value,
  });

  final bool exists;
  final Map<String, dynamic>? parent;
  final String? key;
  final dynamic value;
}
