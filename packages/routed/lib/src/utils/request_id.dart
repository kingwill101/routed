import 'dart:math';

/// A class that generates unique request IDs.
class RequestId {
  /// A secure random number generator.
  static final _random = Random.secure();

  /// A constant string containing all possible characters for the random part of the ID.
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Generates a unique request ID.
  ///
  /// The generated ID consists of a timestamp and a random string.
  /// The [length] parameter specifies the total length of the generated ID.
  /// The default length is 16 characters.
  ///
  /// The timestamp is represented in base-36 and is derived from the current
  /// time in microseconds since epoch. The random string is generated using
  /// characters from [_chars].
  ///
  /// Example:
  /// ```dart
  /// String requestId = RequestId.generate();
  /// ```
  static String generate([int length = 16]) {
    // Get the current timestamp in microseconds since epoch and convert it to a base-36 string.
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    // Generate a random string of the required length minus the length of the timestamp.
    final random = List.generate(
      length - timestamp.length,
      (index) => _chars[_random.nextInt(_chars.length)],
    ).join();

    // Combine the timestamp and the random string to form the final ID.
    return '$timestamp$random';
  }
}
