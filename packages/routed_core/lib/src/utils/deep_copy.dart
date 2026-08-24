/// Utilities for deeply copying nested data structures without
/// sharing references between maps and lists.
dynamic deepCopyValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return deepCopyMap(value);
  }
  if (value is Map) {
    final copy = <dynamic, dynamic>{};
    value.forEach((key, dynamic element) {
      copy[key] = deepCopyValue(element);
    });
    return copy;
  }
  if (value is Iterable) {
    return value.map(deepCopyValue).toList();
  }
  return value;
}

/// Creates a recursive copy of [source] and its nested values.
Map<String, dynamic> deepCopyMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    result[key] = deepCopyValue(value);
  });
  return result;
}

/// Creates a recursive copy of the values in [source].
List<dynamic> deepCopyList(Iterable<dynamic> source) {
  return source.map(deepCopyValue).toList();
}
