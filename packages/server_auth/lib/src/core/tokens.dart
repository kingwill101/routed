import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

/// Generates a cryptographically secure random token.
///
/// [length] is the number of random bytes and defaults to 32. The bytes come
/// from [Random.secure] and are returned as padded URL-safe base64. A negative
/// [length] causes [List.generate] to throw [RangeError].
String secureRandomToken({int length = 32}) {
  final rand = Random.secure();
  final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
  return base64UrlEncode(bytes);
}

/// Encodes [bytes] as URL-safe base64 with all `=` padding removed.
String base64UrlNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Hashes an opaque authentication token for safe persistence.
///
/// Authentication tokens are generated with enough entropy that an unsalted
/// SHA-256 digest is suitable for lookup. The digest is never used as a
/// password verifier, and the random token remains the secret held by the
/// client. Stores should persist this digest instead of the raw token.
String hashOpaqueToken(String token) {
  return base64UrlNoPadding(sha256.convert(utf8.encode(token)).bytes);
}

/// Compares secret-shaped strings without returning early on their content or
/// length. Hashing first keeps the comparison loop fixed-width.
bool constantTimeStringEquals(String left, String right) {
  final leftDigest = sha256.convert(utf8.encode(left)).bytes;
  final rightDigest = sha256.convert(utf8.encode(right)).bytes;
  var difference = 0;
  for (var index = 0; index < leftDigest.length; index++) {
    difference |= leftDigest[index] ^ rightDigest[index];
  }
  return difference == 0;
}

/// Computes an OAuth PKCE S256 code challenge for [verifier].
///
/// The UTF-8 verifier is hashed with SHA-256 and encoded as unpadded
/// URL-safe base64 according to RFC 7636.
String pkceS256CodeChallenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier)).bytes;
  return base64UrlNoPadding(digest);
}
