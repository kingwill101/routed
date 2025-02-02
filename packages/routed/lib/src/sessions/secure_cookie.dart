import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// A simplified "SecureCookie" class that only signs data with an HMAC key.
/// Note: Gorilla also supports optional AES encryption; you could add that.
class SecureCookie {
  /// The hash key used for HMAC, typically 32 or 64 random bytes.
  final List<int> hashKey;

  /// The HMAC instance used for signing and verifying data.
  final Hmac hmac;

  /// Private constructor for SecureCookie.
  SecureCookie._(this.hashKey, this.hmac);

  /// Factory constructor to create a new SecureCookie with the provided hash key.
  /// The hashKey is used for HMAC.
  factory SecureCookie(List<int> hashKey) {
    final hmac = Hmac(sha256, hashKey);
    return SecureCookie._(hashKey, hmac);
  }

  /// Encode session values into a signed string.
  /// The session values are JSON-encoded and then signed to produce "data|signature".
  ///
  /// [name] is the name of the cookie.
  /// [values] is a map containing the session values to be encoded.
  /// Returns a base64Url encoded string containing the payload and its signature.
  String encode(String name, Map<String, dynamic> values) {
    final payload = jsonEncode(values);
    final signature = _sign(payload);
    return base64Url.encode(utf8.encode('$payload|$signature'));
  }

  /// Decode a signed string back into session values, verifying the HMAC.
  ///
  /// [name] is the name of the cookie.
  /// [cookieValue] is the base64Url encoded string containing the payload and its signature.
  /// Returns a map containing the decoded session values.
  /// Throws an exception if the cookie format is invalid or the signature does not match.
  Map<String, dynamic> decode(String name, String cookieValue) {
    try {
      final decodedBytes = base64Url.decode(cookieValue);
      final decodedStr = utf8.decode(decodedBytes);

      final parts = decodedStr.split('|');
      if (parts.length != 2) {
        throw Exception('Invalid cookie format');
      }
      final payload = parts[0];
      final signature = parts[1];

      // Verify the signature
      if (!_verify(payload, signature)) {
        throw Exception('Signature mismatch');
      }

      // Parse the JSON payload
      final Map<String, dynamic> data = jsonDecode(payload);
      return data;
    } catch (e) {
      // Re-throw the caught exception
      rethrow;
    }
  }

  /// Sign the given payload using HMAC.
  ///
  /// [payload] is the string to be signed.
  /// Returns a base64Url encoded string of the HMAC signature.
  String _sign(String payload) {
    final bytes = utf8.encode(payload);
    final mac = hmac.convert(bytes);
    return base64Url.encode(mac.bytes);
  }

  /// Verify the given payload against the provided signature.
  ///
  /// [payload] is the string that was signed.
  /// [signature] is the base64Url encoded HMAC signature to verify against.
  /// Returns true if the signature matches, false otherwise.
  bool _verify(String payload, String signature) {
    final expectedSig = _sign(payload);
    return constantTimeEquals(signature, expectedSig);
  }

  /// Perform a constant-time comparison to avoid timing attacks.
  ///
  /// [a] and [b] are the strings to compare.
  /// Returns true if the strings are equal, false otherwise.
  bool constantTimeEquals(String a, String b) {
    final aBytes = a.codeUnits;
    final bBytes = b.codeUnits;
    if (aBytes.length != bBytes.length) return false;
    var result = 0;
    for (var i = 0; i < aBytes.length; i++) {
      result |= (aBytes[i] ^ bBytes[i]);
    }
    return result == 0;
  }

  /// Generate a random key of the specified length.
  ///
  /// [length] is the length of the random key to generate.
  /// Returns a list of random integers representing the key.
  static List<int> generateRandomKey(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}
