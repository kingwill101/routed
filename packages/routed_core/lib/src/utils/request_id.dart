import 'dart:math';

/// A class that generates unique request IDs.
class RequestId {
  /// Fast random number generator for request IDs.
  static final _random = Random();

  /// Secure random number generator for opt-in secure IDs.
  static final _secureRandom = Random.secure();

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
  static String generate([int length = 16]) {
    return _generate(length, _random);
  }

  /// Generates a secure request ID using a cryptographic RNG.
  static String generateSecure([int length = 16]) {
    return _generate(length, _secureRandom);
  }

  static String _generate(int length, Random random) {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final randomPart = List.generate(
      length - timestamp.length,
      (index) => _chars[random.nextInt(_chars.length)],
    ).join();
    return '$timestamp$randomPart';
  }
}
