/// Returns `true` when a proxy-forwarded value indicates HTTPS.
bool headerIndicatesHttps(String? value) {
  if (value == null || value.isEmpty) {
    return false;
  }

  final candidates = value
      .split(',')
      .map((entry) => entry.trim().toLowerCase())
      .where((entry) => entry.isNotEmpty);

  for (final candidate in candidates) {
    final normalized = candidate.replaceAll('"', '');
    if (normalized == 'https' || normalized == 'https://') {
      return true;
    }
  }
  return false;
}

/// Returns `true` when an RFC 7239 `Forwarded` header indicates HTTPS.
bool forwardedHeaderIndicatesHttps(String? forwardedHeader) {
  if (forwardedHeader == null || forwardedHeader.isEmpty) {
    return false;
  }

  final segments = forwardedHeader
      .split(',')
      .expand((segment) => segment.split(';'))
      .map((pair) => pair.trim().toLowerCase());

  for (final segment in segments) {
    if (!segment.startsWith('proto=')) {
      continue;
    }

    final value = segment.substring('proto='.length).trim().replaceAll('"', '');
    if (value == 'https') {
      return true;
    }
  }

  return false;
}

/// Determines whether a request should be treated as secure (HTTPS).
bool isSecureTransport({
  required String scheme,
  required bool proxySupportEnabled,
  required bool remoteIsTrustedProxy,
  String? forwardedProto,
  String? forwardedScheme,
  String? cloudFrontForwardedProto,
  String? forwarded,
  String? frontEndHttps,
  String? xForwardedSsl,
}) {
  if (scheme == 'https') {
    return true;
  }

  if (!proxySupportEnabled || !remoteIsTrustedProxy) {
    return false;
  }

  if (headerIndicatesHttps(forwardedProto) ||
      headerIndicatesHttps(forwardedScheme) ||
      headerIndicatesHttps(cloudFrontForwardedProto) ||
      forwardedHeaderIndicatesHttps(forwarded)) {
    return true;
  }

  if (frontEndHttps != null && frontEndHttps.toLowerCase() == 'on') {
    return true;
  }

  if (xForwardedSsl != null && xForwardedSsl.toLowerCase() == 'on') {
    return true;
  }

  return false;
}
