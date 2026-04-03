import 'dart:convert';

import 'timing.dart';

/// Parsed credentials from an HTTP Basic Authorization header.
class BasicAuthCredentials {
  const BasicAuthCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

/// Builds a `WWW-Authenticate` challenge value for basic auth.
String basicAuthChallengeHeader(String realm) => 'Basic realm="$realm"';

/// Parses an HTTP Basic auth header into credentials.
///
/// Returns `null` when the header is missing, malformed, or cannot be decoded.
BasicAuthCredentials? parseBasicAuthHeader(String? authHeader) {
  if (authHeader == null || !authHeader.startsWith('Basic ')) {
    return null;
  }

  final encoded = authHeader.substring(6).trim();
  if (encoded.isEmpty) {
    return null;
  }

  try {
    final decoded = utf8.decode(base64.decode(encoded));
    final separator = decoded.indexOf(':');
    if (separator < 0) {
      return null;
    }

    final username = decoded.substring(0, separator);
    final password = decoded.substring(separator + 1);
    if (username.isEmpty) {
      return null;
    }

    return BasicAuthCredentials(username: username, password: password);
  } catch (_) {
    return null;
  }
}

/// Validates parsed credentials against the provided account map.
bool validateBasicAuthCredentials(
  BasicAuthCredentials credentials,
  Map<String, String> accounts,
) {
  final expected = accounts[credentials.username];
  if (expected == null) {
    return false;
  }
  return timingSafeEquals(expected, credentials.password);
}
