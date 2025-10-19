import 'dart:io';

/// An extension on the [HttpHeaders] class to provide additional functionality.
extension HttpHeaderExtension on HttpHeaders {
  /// Converts the [HttpHeaders] to a [Map] where the keys are header names
  /// and the values are lists of header values.
  ///
  /// This method iterates over each header in the [HttpHeaders] and adds
  /// them to a [Map]. The keys in the map are the header names (as [String]),
  /// and the values are lists of header values (as [List<String>]).
  ///
  /// Returns:
  ///   A [Map<String, List<String>>] representing the headers.
  Map<String, List<String>> toMap() {
    // Initialize an empty map to store the headers.
    final map = <String, List<String>>{};

    // Iterate over each header in the HttpHeaders.
    // Preserve duplicates by appending or creating new distinct keys with same name
    forEach((key, value) {
      final existingKey = map.keys.firstWhere(
        (k) => k.toLowerCase() == key.toLowerCase(),
        orElse: () => key,
      );
      final list = map.putIfAbsent(existingKey, () => <String>[]);
      list.addAll(value.toList());
    });

    // Return the map containing all headers.
    return map;
  }
}
