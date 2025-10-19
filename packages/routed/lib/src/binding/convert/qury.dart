import 'dart:convert';

/// Decodes a query string (e.g. "?foo=bar&num=42&...") into a `Map<String, dynamic>`.
/// This class extends the [Converter] class to provide a custom implementation
/// for decoding query strings into a map.
class QueryParamsDecoder extends Converter<String, Map<String, dynamic>> {
  /// Creates a constant [QueryParamsDecoder] instance.
  const QueryParamsDecoder();

  /// Converts the input query string into a `Map<String, dynamic>`.
  ///
  /// - If the input is empty, returns an empty map.
  /// - Removes the leading '?' character if present.
  /// - Splits the query string by '&' to get individual key-value pairs.
  /// - Decodes each key and value using `Uri.decodeComponent`.
  /// - Parses the value into its appropriate type (int, double, bool, list, or string).
  @override
  Map<String, dynamic> convert(String input) {
    if (input.isEmpty) return {};

    // Remove leading '?' if present
    final cleanQuery = input.startsWith('?') ? input.substring(1) : input;
    if (cleanQuery.isEmpty) return {};

    final result = <String, dynamic>{};

    for (final segment in cleanQuery.split('&')) {
      if (segment.isEmpty) continue;
      final parts = segment.split('=');
      if (parts.length != 2) continue; // malformed

      final key = Uri.decodeComponent(parts[0]);
      final value = Uri.decodeComponent(parts[1]);

      result[key] = _parseValue(value);
    }

    return result;
  }

  /// Parses the value from a string into its appropriate type.
  ///
  /// - Attempts to parse the value as an integer.
  /// - If unsuccessful, attempts to parse the value as a double.
  /// - If unsuccessful, attempts to parse the value as a boolean.
  /// - If the value contains commas, splits it into a list and parses each element.
  /// - If all parsing attempts fail, returns the value as a string.
  dynamic _parseValue(String value) {
    // Attempt int
    final intValue = int.tryParse(value);
    if (intValue != null) return intValue;

    // Attempt double
    final doubleValue = double.tryParse(value);
    if (doubleValue != null) return doubleValue;

    // Attempt bool
    final lower = value.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;

    // If the value has commas, you might consider splitting into a list:
    if (value.contains(',')) {
      return value.split(',').map((e) => _parseValue(e)).toList();
    }

    // Fallback to string
    return value;
  }
}

/// A codec that encodes and decodes query strings with special handling for objects
/// that implement [QueryEncodable].
///
/// This class extends the [Codec] class to provide custom implementations for
/// encoding and decoding query strings.
class QueryParamsCodec extends Codec<Map<String, dynamic>, String> {
  /// Creates a constant [QueryParamsCodec] instance.
  const QueryParamsCodec();

  /// Returns an instance of [QueryParamsDecoder] for decoding query strings.
  @override
  QueryParamsDecoder get decoder => const QueryParamsDecoder();

  /// Returns an instance of [QueryParamsEncoder] for encoding query strings.
  @override
  QueryParamsEncoder get encoder => const QueryParamsEncoder();
}

/// Interface for objects that know how to encode themselves to query parameters.
///
/// Classes that implement this interface should provide a `toQuery` method
/// that returns a map representation suitable for query encoding.
abstract class QueryEncodable {
  /// Returns a `Map<String, dynamic>` representation suitable for query encoding.
  Map<String, dynamic> toQuery();
}

/// (Optional) Interface for objects that know how to decode themselves
/// from a map of query parameters. This can be used in more advanced scenarios.
///
/// Classes that implement this interface should provide a `fromQuery` method
/// that returns a new instance of the class from the provided map.
abstract class QueryDecodable<T> {
  /// Returns a new instance of [T] from the provided map of query parameters.
  T fromQuery(Map<String, dynamic> map);
}

/// Attempts to convert [value] into a query-friendly form, recursively.
///
/// - If the value is `null`, returns an empty string.
/// - If the value is a primitive type (`String`, `num`, `bool`), returns it directly.
/// - If the value implements [QueryEncodable], calls `toQuery()` and recurses on the resulting map.
/// - If the value is a `List`, converts each element.
/// - If the value is a `Map`, converts each value.
/// - Otherwise, returns the result of `toString()`.
dynamic _toEncodable(dynamic value) {
  if (value == null) return '';

  if (value is String || value is num || value is bool) {
    return value;
  }

  // If the object has a `toQuery()` method (via the `QueryEncodable` interface),
  // convert it to a Map<String, dynamic> first, then recurse.
  if (value is QueryEncodable) {
    return _toEncodable(value.toQuery());
  }

  // Recursively handle lists
  if (value is List) {
    return value.map((e) => _toEncodable(e)).toList();
  }

  // Recursively handle maps
  if (value is Map) {
    final result = <String, dynamic>{};
    value.forEach((k, v) {
      // Keys must be strings to become query keys
      final keyString = k?.toString() ?? '';
      result[keyString] = _toEncodable(v);
    });
    return result;
  }

  // Fallback
  return value.toString();
}

/// Encodes a `Map<String, dynamic>` into a query string, but first
/// recursively converts objects that implement [QueryEncodable] via `toQuery()`.
///
/// This class extends the [Converter] class to provide a custom implementation
/// for encoding maps into query strings.
class QueryParamsEncoder extends Converter<Map<String, dynamic>, String> {
  /// Creates a constant [QueryParamsEncoder] instance.
  const QueryParamsEncoder();

  /// Converts the input map into a query string.
  ///
  /// - If the input map is empty, returns an empty string.
  /// - First, converts everything to a "plain" map of `String -> String` or `String -> List`, etc.
  /// - Then produces the final query string by encoding each key and value.
  @override
  String convert(Map<String, dynamic> input) {
    if (input.isEmpty) return '';

    // First, convert everything to a "plain" map of String->String or String->List, etc
    final flattenedMap = _toEncodable(input) as Map<String, dynamic>;

    // Then produce the final query string
    return flattenedMap.entries
        .map((entry) {
          final key = Uri.encodeComponent(entry.key);
          final value = _encodeValue(entry.value);
          return '$key=$value';
        })
        .join('&');
  }

  /// Encodes the value into a query-friendly string.
  ///
  /// - If the value is `null`, returns an empty string.
  /// - If the value is a list, joins the elements with commas and encodes the result.
  /// - Otherwise, converts the value to a string and encodes it.
  String _encodeValue(dynamic value) {
    if (value == null) return '';

    if (value is List) {
      // If it's a list of primitives, we join with commas.
      // Or you might handle them differently if you prefer repeated keys (e.g. key=val1&key=val2).
      return Uri.encodeComponent(value.join(','));
    }

    // Everything else, just convert to string
    return Uri.encodeComponent(value.toString());
  }
}
