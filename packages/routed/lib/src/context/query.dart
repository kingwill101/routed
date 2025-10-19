part of 'context.dart';

extension QueryMethods on EngineContext {
  /// Retrieve a query parameter by key.
  T? getQuery<T>(String key) {
    final value = queryCache[key];
    if (value == null) return null;

    // Check if the value is empty, if it has that property
    bool isEmpty = false;
    if (value is String) {
      isEmpty = value.isEmpty;
    } else if (value is List) {
      isEmpty = value.isEmpty;
    } else if (value is Map) {
      isEmpty = value.isEmpty;
    }

    if (isEmpty) return null;
    return value as T;
  }

  /// Retrieve an array of query parameters by key.
  List<String> getQueryArray(String key) {
    final values = getQuery<List<String>>(key);
    if (values == null) return [];
    return values;
  }

  /// Get a query parameter with a default fallback.
  T defaultQuery<T>(String key, T defaultValue) {
    final result = getQuery<T>(key);
    if (result == null) return defaultValue;
    return result;
  }

  /// Get all values for a query key.
  List<String> queryArray(String key) {
    return getQueryArray(key);
  }

  /// Get a map of query parameters with a key prefix.
  Map<String, String> queryMap(String keyPrefix) {
    return getQueryMap(keyPrefix).$1;
  }

  /// Get a map of query parameters with an existence flag.
  (Map<String, String>, bool) getQueryMap(String keyPrefix) {
    final result = <String, String>{};
    var found = false;

    for (final entry in request.uri.queryParametersAll.entries) {
      if (entry.key.startsWith(keyPrefix)) {
        found = true;
        if (entry.value.isNotEmpty) {
          result[entry.key] = entry.value.first;
        }
      }
    }

    return (result, found);
  }
}
