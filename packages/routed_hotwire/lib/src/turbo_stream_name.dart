import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Contract for types that can provide a stable identifier for Turbo streams.
abstract class TurboStreamIdentifiable {
  String get turboStreamIdentifier;
}

/// Builds a canonical stream name from the provided [streamables].
String buildTurboStreamName(Iterable<Object?> streamables) {
  final segments = <String>[];

  void visit(Object? value) {
    if (value == null) return;
    if (value is TurboStreamIdentifiable) {
      final identifier = value.turboStreamIdentifier.trim();
      if (identifier.isNotEmpty) segments.add(identifier);
      return;
    }
    if (value is Iterable && value is! String) {
      for (final element in value) {
        visit(element);
      }
      return;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      segments.add(text);
    }
  }

  for (final value in streamables) {
    visit(value);
  }

  return segments.join(':');
}

/// Signs the Turbo stream name derived from [streamables].
String signTurboStreamName(Iterable<Object?> streamables) {
  final name = buildTurboStreamName(streamables);
  final payload = utf8.encode(name);
  final payloadEncoded = base64UrlEncode(payload);
  final signature = _sign(payload);
  return '$payloadEncoded--$signature';
}

/// Verifies a signed stream [name] and returns the original stream name if valid.
String? verifyTurboStreamName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final parts = name.split('--');
  if (parts.length != 2) return null;

  late List<int> payloadBytes;
  late List<int> providedSignature;
  try {
    payloadBytes = base64Url.decode(base64Url.normalize(parts[0]));
    providedSignature = base64Url.decode(base64Url.normalize(parts[1]));
  } on FormatException {
    return null;
  }

  final expectedSignature = Hmac(
    sha256,
    _secretBytes,
  ).convert(payloadBytes).bytes;
  if (!_timingSafeEquals(expectedSignature, providedSignature)) {
    return null;
  }

  return utf8.decode(payloadBytes);
}

/// Generates the markup for a `<turbo-cable-stream-source>` subscription tag.
String turboStreamSourceTag({
  required Iterable<Object?> streamables,
  String channel = 'Turbo::StreamsChannel',
  Map<String, String>? dataAttributes,
}) {
  final signed = signTurboStreamName(streamables);
  final buffer = StringBuffer()
    ..write('<turbo-cable-stream-source channel="')
    ..write(channel)
    ..write('" signed-stream-name="')
    ..write(signed)
    ..write('"');

  if (dataAttributes != null && dataAttributes.isNotEmpty) {
    dataAttributes.forEach((key, value) {
      if (value.isEmpty) return;
      buffer
        ..write(' data-')
        ..write(_attributeName(key))
        ..write('="')
        ..write(_escapeAttribute(value))
        ..write('"');
    });
  }

  buffer.write('></turbo-cable-stream-source>');
  return buffer.toString();
}

/// Configures the shared secret used to sign stream names.
set turboStreamSigningSecret(String value) {
  _secretBytes = utf8.encode(value);
}

List<int> _secretBytes = _generateSecret();

String _sign(List<int> payload) {
  final digest = Hmac(sha256, _secretBytes).convert(payload);
  return base64UrlEncode(digest.bytes);
}

List<int> _generateSecret() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes;
}

bool _timingSafeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _attributeName(String value) => value.replaceAll(RegExp(r'[_\s]+'), '-');

String _escapeAttribute(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
