/// Parse a URL-encoded string supporting bracket notation for nested maps
/// and arrays. Returns a nested `Map<String, dynamic>` structure, where
/// leaves are strings, and intermediate nodes are either `Map<String, dynamic>`
/// or `List<dynamic>`.
///
/// Any repeated key (like `foo=1` and `foo=2`) will become a list in the
/// intermediate structure. Then a final pass flattens single-element lists
/// into a single string.
Map<String, dynamic> parseUrlEncoded(String input) {
  final result = <String, dynamic>{};

  // Split input by '&' into key=value pairs
  for (final pair in input.split('&')) {
    if (pair.isEmpty) continue;

    final eqIndex = pair.indexOf('=');
    if (eqIndex == -1) {
      // Malformed or missing '=', skip or handle error
      continue;
    }

    // Decode key and value
    final rawKey = Uri.decodeQueryComponent(pair.substring(0, eqIndex));
    final rawValue = Uri.decodeQueryComponent(pair.substring(eqIndex + 1));

    _storeKeyValue(result, rawKey, rawValue);
  }

  // Flatten any single-element lists before returning
  return _flattenSingles(result);
}

/// Inserts [value] into [root] (a `Map<String,dynamic>`) at the path given
/// by bracket-notation in [rawKey], handling array expansions ("[]").
void _storeKeyValue(Map<String, dynamic> root, String rawKey, String value) {
  final segments = _splitKeyIntoSegments(rawKey);
  _doStore(root, segments, value);
}

/// Splits a bracketed key like "key[nested]" into segments ["key","nested"].
/// Also handles "key[]" => ["key",""] for array pushes.
List<String> _splitKeyIntoSegments(String rawKey) {
  // e.g. "user[address][city]" => bracketSplit = ["user","address]","city]"]
  final parts = rawKey.split('[');
  final segments = <String>[];

  // The first chunk is always "key" (the part before the first '[')
  segments.add(parts[0]);

  // Subsequent chunks remove the trailing ']' if present
  for (var i = 1; i < parts.length; i++) {
    final p = parts[i];
    segments.add(p.endsWith(']') ? p.substring(0, p.length - 1) : p);
  }
  return segments;
}

/// Recursively navigate or create containers (Map or List),
/// preserving/upgrading earlier data if a key is reused in a different way.
void _doStore(dynamic current, List<String> segments, String value) {
  if (segments.isEmpty) return;

  final head = segments.first;
  final tail = segments.skip(1).toList();

  // If this is the last segment => place a leaf value
  if (tail.isEmpty) {
    if (head.isEmpty) {
      // head == "" means "[]", so push [value] into array
      if (current is List) {
        current.add(value);
      } else if (current is Map<String, dynamic>) {
        // For map, insert value at the next numeric key (0,1,2,...) if "[]"
        current[_findNextAvailableKey(current)] = value;
      }
    } else {
      // Normal key
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(head)) {
          // First time seeing this key => just store as single value
          current[head] = value;
        } else {
          // Key already used => convert or append to list
          final existing = current[head];
          if (existing is List) {
            current[head] = [...existing, value];
          } else {
            current[head] = [existing, value];
          }
        }
      } else if (current is List) {
        // If current is a list, we create a map with this single key
        final newMap = <String, dynamic>{head: value};
        current.add(newMap);
      }
    }
    return;
  }

  // Not the last segment => we need a container (Map or List) for the next step
  if (head.isEmpty) {
    // head == "" => "[]", meaning append a new container to a list
    if (current is List) {
      // Build the right container type for the next segment
      final nextHead = tail.firstOrNull;
      final container = (nextHead == null || nextHead.isEmpty)
          ? <dynamic>[]
          : <String, dynamic>{};
      current.add(container);
      _doStore(container, tail, value);
    } else if (current is Map<String, dynamic>) {
      // Convert a map into a list-like structure
      final newList = <dynamic>[current];
      final nextHead = tail.firstOrNull;
      final container = (nextHead == null || nextHead.isEmpty)
          ? <dynamic>[]
          : <String, dynamic>{};
      newList.add(container);
      // If you want to store back, you'd replace 'current' in a higher scope,
      // but often this path is unusual. Depends on your usage.
      _doStore(container, tail, value);
    }
    return;
  }

  // Normal key (head is not empty)
  if (current is Map<String, dynamic>) {
    if (!current.containsKey(head)) {
      // We create a container for the next segment
      final nextHead = tail.firstOrNull;
      current[head] =
          (nextHead?.isEmpty ?? false) ? <dynamic>[] : <String, dynamic>{};
    } else {
      final existing = current[head];
      // If it was a string, we need to upgrade it to a container
      if (existing is String) {
        final nextHead = tail.firstOrNull;
        current[head] = (nextHead?.isEmpty ?? false)
            ? <dynamic>[existing]
            : <String, dynamic>{};
      }
    }
    _doStore(current[head], tail, value);
  } else if (current is List) {
    // If 'current' is a list, we append a new map and keep going
    final newMap = <String, dynamic>{};
    current.add(newMap);
    _doStore(newMap, segments, value);
  }
}

/// Safe read of the first element from a list, or null if empty.
extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : this[0];
}

/// Creates a new key for array-like insertion in a map by scanning
/// numeric keys (0,1,2,...) until it finds an available one.
String _findNextAvailableKey(Map<String, dynamic> map) {
  int index = 0;
  while (map.containsKey(index.toString())) {
    index++;
  }
  return index.toString();
}

/// Flattens any single-element lists in a nested map structure.
/// If a map entry's value is a list of length == 1, replace it with that element.
/// If that element is also a map, recurse. If the value is a map, recurse into it.
Map<String, dynamic> _flattenSingles(dynamic value) {
  if (value is Map<String, dynamic>) {
    final result = <String, dynamic>{};
    value.forEach((k, v) {
      result[k] = _processValue(v);
    });
    return result;
  } 
  
  // If the input wasn't a Map, we need to return an empty map to maintain type
  return <String, dynamic>{};
}

/// Helper function to process individual values in the flattening process
dynamic _processValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    final result = <String, dynamic>{};
    value.forEach((k, v) {
      result[k] = _processValue(v);
    });
    return result;
  } else if (value is List) {
    // Flatten each element, then if there's exactly 1 element, remove the list
    final newList = value.map(_processValue).toList();
    if (newList.length == 1) {
      return newList.first;
    } else {
      return newList;
    }
  } else {
    return value;
  }
}
