import 'dart:convert';
import 'dart:math';

/// Generates a URL-safe random token suitable for CSRF cookies/headers.
String generateCsrfToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(bytes);
}
