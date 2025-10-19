import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../engine/config.dart';

/// Outcome of evaluating conditional request headers.
enum ConditionalOutcome { proceed, notModified, preconditionFailed }

class _EtagCandidate {
  const _EtagCandidate({
    this.value,
    this.weak = false,
    this.isWildcard = false,
  });

  final String? value;
  final bool weak;
  final bool isWildcard;

  bool get hasValue => value != null;
}

_EtagCandidate? _parseCurrentEtag(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return _parseEtag(value);
}

List<_EtagCandidate> _parseEtagList(List<String> values) {
  final candidates = <_EtagCandidate>[];
  for (final entry in values) {
    final segments = entry.split(',');
    for (final raw in segments) {
      final candidate = _parseEtag(raw);
      if (candidate != null) {
        candidates.add(candidate);
      }
    }
  }
  return candidates;
}

_EtagCandidate? _parseEtag(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value == '*') {
    return const _EtagCandidate(isWildcard: true);
  }
  var weak = false;
  if (value.length > 2 && value.substring(0, 2).toLowerCase() == 'w/') {
    weak = true;
    value = value.substring(2).trim();
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  return _EtagCandidate(value: value, weak: weak);
}

bool _matchesCandidate(
  _EtagCandidate candidate,
  _EtagCandidate? current, {
  required bool allowWeak,
}) {
  if (candidate.isWildcard) {
    return current != null && current.hasValue;
  }
  if (current == null || !current.hasValue) {
    return false;
  }
  if (!allowWeak && (candidate.weak || current.weak)) {
    return false;
  }
  return candidate.value == current.value;
}

DateTime? _parseHttpDate(String value) {
  try {
    return HttpDate.parse(value).toUtc();
  } catch (_) {
    return null;
  }
}

Digest _hashBytes(List<int> bytes, String algorithm) {
  switch (algorithm.toLowerCase()) {
    case 'sha1':
      return sha1.convert(bytes);
    case 'md5':
      return md5.convert(bytes);
    case 'sha256':
    default:
      return sha256.convert(bytes);
  }
}

/// Generates a strong ETag (quoted string) for the provided byte payload.
String generateStrongEtag(List<int> bytes, {String algorithm = 'sha256'}) {
  final digest = _hashBytes(bytes, algorithm);
  final encoded = base64Url.encode(digest.bytes);
  return '"$encoded"';
}

/// Generates a weak ETag (`W/"..."`) for the provided byte payload.
String generateWeakEtag(List<int> bytes, {String algorithm = 'sha256'}) =>
    'W/${generateStrongEtag(bytes, algorithm: algorithm)}';

/// Generates a strong ETag from the provided [value] (UTF-8 encoded).
String generateStrongEtagFromString(
  String value, {
  String algorithm = 'sha256',
  Encoding encoding = utf8,
}) => generateStrongEtag(encoding.encode(value), algorithm: algorithm);

/// Generates a weak ETag from the provided [value] (UTF-8 encoded).
String generateWeakEtagFromString(
  String value, {
  String algorithm = 'sha256',
  Encoding encoding = utf8,
}) => generateWeakEtag(encoding.encode(value), algorithm: algorithm);

/// Evaluates HTTP conditional request headers and returns the desired outcome.
ConditionalOutcome evaluateConditionals({
  required String method,
  required HttpHeaders headers,
  String? etag,
  DateTime? lastModified,
}) {
  final safeMethod = method == 'GET' || method == 'HEAD';
  final currentEtag = _parseCurrentEtag(etag);
  final currentLastModified = lastModified?.toUtc();

  final ifMatchHeaders = headers[HttpHeaders.ifMatchHeader];
  if (ifMatchHeaders != null && ifMatchHeaders.isNotEmpty) {
    final candidates = _parseEtagList(ifMatchHeaders);
    final matches = candidates.any(
      (candidate) =>
          _matchesCandidate(candidate, currentEtag, allowWeak: false),
    );
    final wildcardAllowed = candidates.any((candidate) => candidate.isWildcard);
    if (!(matches || (wildcardAllowed && currentEtag != null))) {
      return ConditionalOutcome.preconditionFailed;
    }
  }

  final ifUnmodifiedSince = headers.value(HttpHeaders.ifUnmodifiedSinceHeader);
  if (ifUnmodifiedSince != null && currentLastModified != null) {
    final since = _parseHttpDate(ifUnmodifiedSince);
    if (since != null && currentLastModified.isAfter(since)) {
      return ConditionalOutcome.preconditionFailed;
    }
  }

  final ifNoneMatchHeaders = headers[HttpHeaders.ifNoneMatchHeader];
  if (ifNoneMatchHeaders != null && ifNoneMatchHeaders.isNotEmpty) {
    final candidates = _parseEtagList(ifNoneMatchHeaders);
    final matches = candidates.any(
      (candidate) => _matchesCandidate(candidate, currentEtag, allowWeak: true),
    );
    final wildcard = candidates.any((candidate) => candidate.isWildcard);
    if (matches || (wildcard && currentEtag != null)) {
      return safeMethod
          ? ConditionalOutcome.notModified
          : ConditionalOutcome.preconditionFailed;
    }
  } else if (safeMethod) {
    final ifModifiedSince = headers.value(HttpHeaders.ifModifiedSinceHeader);
    if (ifModifiedSince != null && currentLastModified != null) {
      final since = _parseHttpDate(ifModifiedSince);
      if (since != null && !currentLastModified.isAfter(since)) {
        return ConditionalOutcome.notModified;
      }
    }
  }

  return ConditionalOutcome.proceed;
}

/// Resolves a default ETag string based on the configured [strategy].
String? resolveDefaultEtag(
  List<int> bytes,
  EtagStrategy strategy, {
  String algorithm = 'sha256',
}) {
  switch (strategy) {
    case EtagStrategy.disabled:
      return null;
    case EtagStrategy.strong:
      return generateStrongEtag(bytes, algorithm: algorithm);
    case EtagStrategy.weak:
      return generateWeakEtag(bytes, algorithm: algorithm);
  }
}
