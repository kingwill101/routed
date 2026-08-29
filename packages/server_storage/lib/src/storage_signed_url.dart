import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Creates and verifies time-limited URLs for private storage downloads.
///
/// The signature covers the HTTP method, path, expiration, and every
/// non-signature query parameter. Callers should authorize the requested
/// object before issuing a URL; possession of a valid URL grants temporary
/// access to that exact request path on an application using the same secret.
final class StorageSignedUrlSigner {
  /// Creates a HMAC-SHA256 signer from [secret].
  ///
  /// The UTF-8 encoded secret must contain at least 32 bytes. Store it in the
  /// host's secret manager rather than application source or ordinary config.
  StorageSignedUrlSigner(String secret) : _key = utf8.encode(secret) {
    if (_key.length < 32) {
      throw ArgumentError(
        'Signed storage URL secrets must contain at least 32 UTF-8 bytes.',
        'secret',
      );
    }
  }

  final List<int> _key;

  /// Adds an expiration and HMAC signature to [url].
  ///
  /// Existing `expires` or `signature` parameters are rejected so a caller
  /// cannot accidentally create an ambiguous capability URL. `HEAD` and `GET`
  /// share a signature, allowing metadata checks without issuing a second URL.
  Uri sign(
    Uri url, {
    required DateTime expiresAt,
    String method = 'GET',
  }) {
    _validateUrl(url);
    if (url.queryParametersAll.containsKey(_expiresParameter) ||
        url.queryParametersAll.containsKey(_signatureParameter)) {
      throw ArgumentError(
        'Signed URL parameters are reserved.',
        'url',
      );
    }

    final expiration = expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (expiration <= now) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'Expiration must be in the future.',
      );
    }

    final unsigned = url.removeFragment().replace(
      queryParameters: <String, dynamic>{
        for (final entry in url.queryParametersAll.entries)
          entry.key: entry.value,
        _expiresParameter: '$expiration',
      },
    );
    final signature = _signature(unsigned, method);
    return unsigned.replace(
      queryParameters: <String, dynamic>{
        for (final entry in unsigned.queryParametersAll.entries)
          entry.key: entry.value,
        _signatureParameter: signature,
      },
    );
  }

  /// Returns whether [url] has a valid, unexpired signature for [method].
  ///
  /// Malformed encodings, duplicate reserved parameters, traversal segments,
  /// expired URLs, and invalid signatures all return `false`.
  bool verify(
    Uri url, {
    String method = 'GET',
    DateTime? now,
  }) {
    try {
      _validateUrl(url);
      final expiresValues = url.queryParametersAll[_expiresParameter];
      final signatureValues = url.queryParametersAll[_signatureParameter];
      if (expiresValues == null ||
          expiresValues.length != 1 ||
          signatureValues == null ||
          signatureValues.length != 1) {
        return false;
      }

      final expiration = int.tryParse(expiresValues.single);
      if (expiration == null || expiration <= 0) return false;
      final current =
          (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
      if (current >= expiration) return false;

      final provided = base64Url.decode(
        base64Url.normalize(signatureValues.single),
      );
      final unsigned = url.removeFragment().replace(
        queryParameters: <String, dynamic>{
          for (final entry in url.queryParametersAll.entries)
            if (entry.key != _signatureParameter) entry.key: entry.value,
        },
      );
      final expected = base64Url.decode(
        base64Url.normalize(_signature(unsigned, method)),
      );
      return _constantTimeEquals(expected, provided);
    } on Object {
      return false;
    }
  }

  String _signature(Uri url, String method) {
    final canonical = <String>[
      _canonicalMethod(method),
      _canonicalPath(url),
      _canonicalQuery(url),
    ].join('\n');
    final digest = Hmac(sha256, _key).convert(utf8.encode(canonical));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static void _validateUrl(Uri url) {
    if (url.fragment.isNotEmpty || url.userInfo.isNotEmpty) {
      throw ArgumentError(
        'Signed storage URLs cannot contain user info or fragments.',
        'url',
      );
    }
    if (url.pathSegments.any((segment) => segment == '.' || segment == '..')) {
      throw ArgumentError(
        'Signed storage URLs cannot contain traversal segments.',
        'url',
      );
    }
  }

  static String _canonicalMethod(String method) {
    final normalized = method.trim().toUpperCase();
    if (normalized == 'HEAD') return 'GET';
    if (normalized.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Method cannot be empty.');
    }
    return normalized;
  }

  static String _canonicalPath(Uri url) {
    final encoded = Uri(pathSegments: url.pathSegments).path;
    if (!url.path.startsWith('/') || encoded.startsWith('/')) return encoded;
    return '/$encoded';
  }

  static String _canonicalQuery(Uri url) {
    final pairs = <String>[];
    for (final entry in url.queryParametersAll.entries) {
      if (entry.key == _signatureParameter) continue;
      for (final value in entry.value) {
        pairs.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    pairs.sort();
    return pairs.join('&');
  }

  static bool _constantTimeEquals(List<int> expected, List<int> provided) {
    var difference = expected.length ^ provided.length;
    for (var index = 0; index < expected.length; index++) {
      final actual = index < provided.length ? provided[index] : 0;
      difference |= expected[index] ^ actual;
    }
    return difference == 0;
  }
}

const _expiresParameter = 'expires';
const _signatureParameter = 'signature';
