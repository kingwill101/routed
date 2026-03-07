part of 'bridge_runtime.dart';

/// Immutable request-headers implementation backed by a bridge request source.
final class _BridgeRequestHeaders implements HttpHeaders {
  _BridgeRequestHeaders.fromSource(
    _BridgeRequestSource source, {
    required _BridgeRequestMetadata metadata,
    bool stripTransferEncoding = false,
  }) : _source = source,
       _metadata = metadata,
       _stripTransferEncoding = stripTransferEncoding;

  final _BridgeRequestSource _source;
  final _BridgeRequestMetadata _metadata;
  final bool _stripTransferEncoding;
  ({Map<String, List<String>> headers, Map<String, String> originalNames})?
  _materialized;
  _BridgeParsedAuthority? _parsedHostPort;
  bool _parsedHostPortResolved = false;

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
  int get contentLength => _metadata.contentLength;

  @override
  set contentLength(int value) => _immutable();

  @override
  bool get persistentConnection => _metadata.persistentConnection;

  @override
  set persistentConnection(bool value) => _immutable();

  @override
  bool get chunkedTransferEncoding {
    if (_isTransferEncodingStripped(HttpHeaders.transferEncodingHeader)) {
      return false;
    }
    return _metadata.chunkedTransferEncoding;
  }

  @override
  set chunkedTransferEncoding(bool value) => _immutable();

  @override
  List<String>? operator [](String name) {
    if (_isTransferEncodingStripped(name)) {
      return null;
    }
    final values = <String>[];
    _source.forEachMatchingHeader(name, values.add);
    return values.isEmpty ? null : values;
  }

  @override
  String? value(String name) {
    if (_isTransferEncodingStripped(name)) {
      return null;
    }
    String? found;
    var count = 0;
    _source.forEachMatchingHeader(name, (value) {
      count++;
      found ??= value;
    });
    if (count == 0) {
      return null;
    }
    if (count > 1) {
      throw HttpException('More than one value for header $name');
    }
    return found;
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
    final materialized = _materializeHeaders();
    for (final entry in materialized.headers.entries) {
      action(
        materialized.originalNames[entry.key] ?? entry.key,
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
    if (_parsedHostPortResolved) {
      return _parsedHostPort;
    }
    _parsedHostPortResolved = true;
    final raw = _metadata.hostHeader;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _parsedHostPort = _splitBridgeAuthority(raw);
  }

  bool _isTransferEncodingStripped(String name) {
    return _stripTransferEncoding &&
        _equalsAsciiIgnoreCase(name, HttpHeaders.transferEncodingHeader);
  }

  ({Map<String, List<String>> headers, Map<String, String> originalNames})
  _materializeHeaders() {
    final materialized = _materialized;
    if (materialized != null) {
      return materialized;
    }

    final headers = <String, List<String>>{};
    final originalNames = <String, String>{};
    _source.forEachHeader((name, value) {
      if (_isTransferEncodingStripped(name)) {
        return;
      }
      final normalized = _asciiLower(name);
      final values = headers.putIfAbsent(normalized, () => <String>[]);
      values.add(value);
      originalNames[normalized] = name;
    });
    return _materialized = (headers: headers, originalNames: originalNames);
  }
}

bool _headerValueContainsTokenIgnoreCase(String value, String token) {
  var partStart = 0;
  while (partStart <= value.length) {
    var partEnd = partStart;
    while (partEnd < value.length && value.codeUnitAt(partEnd) != 0x2c) {
      partEnd++;
    }

    var start = partStart;
    while (start < partEnd) {
      final codeUnit = value.codeUnitAt(start);
      if (codeUnit != 0x20 && codeUnit != 0x09) {
        break;
      }
      start++;
    }

    var end = partEnd;
    while (end > start) {
      final codeUnit = value.codeUnitAt(end - 1);
      if (codeUnit != 0x20 && codeUnit != 0x09) {
        break;
      }
      end--;
    }

    if (end > start &&
        _equalsAsciiIgnoreCase(value.substring(start, end), token)) {
      return true;
    }

    if (partEnd == value.length) {
      return false;
    }
    partStart = partEnd + 1;
  }
  return false;
}

/// Decodes immutable header view used by [BridgeHttpRequest.headers].
_BridgeRequestHeaders _buildBridgeRequestHeaders(
  _BridgeRequestSource source, {
  required _BridgeRequestMetadata metadata,
  bool stripTransferEncoding = false,
}) {
  return _BridgeRequestHeaders.fromSource(
    source,
    metadata: metadata,
    stripTransferEncoding: stripTransferEncoding,
  );
}
