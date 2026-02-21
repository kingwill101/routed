part of 'bridge_runtime.dart';

/// Immutable request-headers implementation backed by bridge frame data.
final class _BridgeRequestHeaders implements HttpHeaders {
  _BridgeRequestHeaders.fromFrame(
    BridgeRequestFrame frame, {
    bool stripTransferEncoding = false,
  }) {
    for (var i = 0; i < frame.headerCount; i++) {
      final name = frame.headerNameAt(i);
      final normalized = _asciiLower(name);
      final values = _headers.putIfAbsent(normalized, () => <String>[]);
      values.add(frame.headerValueAt(i));
      _originalNames[normalized] = name;
    }
    if (stripTransferEncoding) {
      _headers.remove(HttpHeaders.transferEncodingHeader);
      _originalNames.remove(HttpHeaders.transferEncodingHeader);
    }
  }

  final Map<String, List<String>> _headers = <String, List<String>>{};
  final Map<String, String> _originalNames = <String, String>{};

  @override
  DateTime? get date => _parseDate(HttpHeaders.dateHeader);

  @override
  set date(DateTime? value) => _immutable();

  @override
  DateTime? get expires => _parseDate(HttpHeaders.expiresHeader);

  @override
  set expires(DateTime? value) => _immutable();

  @override
  DateTime? get ifModifiedSince =>
      _parseDate(HttpHeaders.ifModifiedSinceHeader);

  @override
  set ifModifiedSince(DateTime? value) => _immutable();

  @override
  String? get host {
    final parsed = _parseHostPort();
    return parsed?.host;
  }

  @override
  set host(String? value) => _immutable();

  @override
  int? get port {
    final parsed = _parseHostPort();
    return parsed?.port;
  }

  @override
  set port(int? value) => _immutable();

  @override
  ContentType? get contentType {
    final raw = value(HttpHeaders.contentTypeHeader);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return ContentType.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  set contentType(ContentType? value) => _immutable();

  @override
  int get contentLength {
    final raw = value(HttpHeaders.contentLengthHeader);
    if (raw == null || raw.isEmpty) {
      return -1;
    }
    return int.tryParse(raw.trim()) ?? -1;
  }

  @override
  set contentLength(int value) => _immutable();

  @override
  bool get persistentConnection {
    final values = _headers[_asciiLower(HttpHeaders.connectionHeader)];
    if (values == null || values.isEmpty) {
      return true;
    }
    if (_containsTokenIgnoreCase(values, 'close')) {
      return false;
    }
    if (_containsTokenIgnoreCase(values, 'keep-alive')) {
      return true;
    }
    return true;
  }

  @override
  set persistentConnection(bool value) => _immutable();

  @override
  bool get chunkedTransferEncoding {
    final values = _headers[_asciiLower(HttpHeaders.transferEncodingHeader)];
    if (values == null || values.isEmpty) {
      return false;
    }
    return _containsTokenIgnoreCase(values, 'chunked');
  }

  @override
  set chunkedTransferEncoding(bool value) => _immutable();

  @override
  List<String>? operator [](String name) {
    final values = _headers[_asciiLower(name)];
    return values == null ? null : List<String>.of(values);
  }

  @override
  String? value(String name) {
    final values = _headers[_asciiLower(name)];
    if (values == null || values.isEmpty) {
      return null;
    }
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _immutable();

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _immutable();

  @override
  void remove(String name, Object value) => _immutable();

  @override
  void removeAll(String name) => _immutable();

  @override
  void forEach(void Function(String name, List<String> values) action) {
    for (final entry in _headers.entries) {
      action(
        _originalNames[entry.key] ?? entry.key,
        List<String>.of(entry.value),
      );
    }
  }

  @override
  void noFolding(String name) => _immutable();

  @override
  void clear() => _immutable();

  Never _immutable() {
    throw UnsupportedError('Request headers are immutable');
  }

  DateTime? _parseDate(String name) {
    final raw = value(name);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return null;
    }
  }

  _BridgeParsedAuthority? _parseHostPort() {
    final raw = value(HttpHeaders.hostHeader);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _splitBridgeAuthority(raw);
  }

  bool _containsTokenIgnoreCase(List<String> values, String token) {
    final target = _asciiLower(token);
    for (final value in values) {
      for (final part in value.split(',')) {
        if (_asciiLower(part.trim()) == target) {
          return true;
        }
      }
    }
    return false;
  }
}

/// Decodes immutable header view used by [BridgeHttpRequest.headers].
_BridgeRequestHeaders _buildBridgeRequestHeaders(
  BridgeRequestFrame frame, {
  bool stripTransferEncoding = false,
}) {
  return _BridgeRequestHeaders.fromFrame(
    frame,
    stripTransferEncoding: stripTransferEncoding,
  );
}
