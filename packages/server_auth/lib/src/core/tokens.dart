import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

/// Generates a cryptographically secure random token.
String secureRandomToken({int length = 32}) {
  final rand = Random.secure();
  final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
  return base64UrlEncode(bytes);
}

/// Encodes bytes as URL-safe base64 without padding.
String base64UrlNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Computes an OAuth PKCE S256 code challenge for [verifier].
String pkceS256CodeChallenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier)).bytes;
  return base64UrlNoPadding(digest);
}
