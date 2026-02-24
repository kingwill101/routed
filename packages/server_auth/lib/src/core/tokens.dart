import 'dart:convert';
import 'dart:math';

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
