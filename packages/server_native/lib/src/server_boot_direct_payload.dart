part of 'server_boot.dart';

/// Non-owning byte range into a payload.
final class _ByteSlice {
  const _ByteSlice(this.start, this.end);

  final int start;
  final int end;
}

/// Decoded field metadata (`slice + next offset`).
final class _ParsedField {
  const _ParsedField(this.slice, this.nextOffset);

  final _ByteSlice slice;
  final int nextOffset;
}

/// Zero-copy view over a direct request bridge payload.
final class _DirectPayloadRequestView {
  _DirectPayloadRequestView._({
    required Uint8List payload,
    required bool tokenizedHeaderNames,
  }) : _payload = payload,
       _tokenizedHeaderNames = tokenizedHeaderNames;

  /// Validates frame metadata and returns a lazy request view.
  factory _DirectPayloadRequestView.parse(Uint8List payload) {
    if (payload.length < 2) {
      throw const FormatException('truncated bridge payload');
    }
    final version = payload[0];
    if (version != bridgeFrameProtocolVersion) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = payload[1];
    final tokenized = frameType == _bridgeRequestFrameTypeTokenized;
    if (frameType != _bridgeRequestFrameTypeLegacy && !tokenized) {
      throw FormatException('invalid bridge request frame type: $frameType');
    }

    return _DirectPayloadRequestView._(
      payload: payload,
      tokenizedHeaderNames: tokenized,
    );
  }

  final Uint8List _payload;
  final bool _tokenizedHeaderNames;
  _ByteSlice? _methodRange;
  _ByteSlice? _schemeRange;
  _ByteSlice? _authorityRange;
  _ByteSlice? _pathRange;
  _ByteSlice? _queryRange;
  _ByteSlice? _protocolRange;
  int? _headerCount;
  int? _headersOffset;

  String? _method;
  String? _scheme;
  String? _authority;
  String? _path;
  String? _query;
  String? _protocol;
  List<MapEntry<String, String>>? _headers;
  _ByteSlice? _bodyRange;
  Uint8List? _bodyBytes;

  String get method {
    _ensureHeadParsed();
    return _method ??= _readFieldOrDefault(_methodRange!, 'GET');
  }

  String get scheme {
    _ensureHeadParsed();
    return _scheme ??= _readFieldOrDefault(_schemeRange!, 'http');
  }

  String get authority {
    _ensureHeadParsed();
    return _authority ??= _readFieldOrDefault(_authorityRange!, '127.0.0.1');
  }

  String get path {
    _ensureHeadParsed();
    return _path ??= _readFieldOrDefault(_pathRange!, '/');
  }

  String get query {
    _ensureHeadParsed();
    return _query ??= _readFieldString(_queryRange!);
  }

  String get protocol {
    _ensureHeadParsed();
    return _protocol ??= _readFieldOrDefault(_protocolRange!, '1.1');
  }

  Uint8List get bodyBytes {
    final range = _bodyRange ??= _parseBodyRange();
    return _bodyBytes ??= Uint8List.sublistView(
      _payload,
      range.start,
      range.end,
    );
  }

  /// Materializes all headers into an immutable value list once.
  List<MapEntry<String, String>> materializeHeaders() {
    final cached = _headers;
    if (cached != null) {
      return cached;
    }
    _ensureHeadParsed();
    final headerCount = _headerCount!;
    final headers = List<MapEntry<String, String>>.filled(
      headerCount,
      const MapEntry('', ''),
      growable: false,
    );
    var offset = _headersOffset!;
    for (var i = 0; i < headerCount; i++) {
      final parsed = _readHeaderAt(offset);
      headers[i] = MapEntry(parsed.name, parsed.value);
      offset = parsed.nextOffset;
    }
    _headers = headers;
    return headers;
  }

  /// Returns the first header value matching [name], or `null`.
  String? header(String name) {
    _ensureHeadParsed();
    final tokenLookup = _tokenizedHeaderNames
        ? _directHeaderLookupToken(name)
        : null;
    if (tokenLookup != null) {
      final value = _readTokenizedHeaderValueByToken(name, tokenLookup);
      if (value != null) {
        return value;
      }
    }
    var offset = _headersOffset!;
    for (var i = 0; i < _headerCount!; i++) {
      final parsed = _readHeaderAt(offset);
      if (_equalsAsciiIgnoreCase(parsed.name, name)) {
        return parsed.value;
      }
      offset = parsed.nextOffset;
    }
    return null;
  }

  String? _readTokenizedHeaderValueByToken(String name, int tokenLookup) {
    var offset = _headersOffset!;
    for (var i = 0; i < _headerCount!; i++) {
      if (offset + 2 > _payload.length) {
        throw const FormatException('truncated bridge payload');
      }
      final token = (_payload[offset] << 8) | _payload[offset + 1];
      offset += 2;

      var matches = false;
      if (token == _bridgeHeaderNameLiteralToken) {
        final nameField = _readField(_payload, offset);
        final parsedName = _readFieldString(nameField.slice);
        matches = _equalsAsciiIgnoreCase(parsedName, name);
        offset = nameField.nextOffset;
      } else {
        if (token < 0 || token >= _directBridgeHeaderNameTable.length) {
          throw FormatException('invalid bridge header name token: $token');
        }
        matches = token == tokenLookup;
      }

      final valueField = _readField(_payload, offset);
      if (matches) {
        return _readFieldString(valueField.slice);
      }
      offset = valueField.nextOffset;
    }
    return null;
  }

  String _readFieldOrDefault(_ByteSlice range, String fallback) {
    if (range.start == range.end) {
      return fallback;
    }
    return _readFieldString(range);
  }

  @pragma('vm:prefer-inline')
  String _readFieldString(_ByteSlice range) {
    for (var i = range.start; i < range.end; i++) {
      if (_payload[i] > 0x7f) {
        return _directStrictUtf8Decoder.convert(
          _payload,
          range.start,
          range.end,
        );
      }
    }
    return String.fromCharCodes(_payload, range.start, range.end);
  }

  _ParsedHeader _readHeaderAt(int offset) {
    late final String name;
    if (!_tokenizedHeaderNames) {
      final nameField = _readField(_payload, offset);
      name = _readFieldString(nameField.slice);
      offset = nameField.nextOffset;
    } else {
      if (offset + 2 > _payload.length) {
        throw const FormatException('truncated bridge payload');
      }
      final token = (_payload[offset] << 8) | _payload[offset + 1];
      offset += 2;
      if (token == _bridgeHeaderNameLiteralToken) {
        final nameField = _readField(_payload, offset);
        name = _readFieldString(nameField.slice);
        offset = nameField.nextOffset;
      } else {
        if (token < 0 || token >= _directBridgeHeaderNameTable.length) {
          throw FormatException('invalid bridge header name token: $token');
        }
        name = _directBridgeHeaderNameTable[token];
      }
    }

    final valueField = _readField(_payload, offset);
    final value = _readFieldString(valueField.slice);
    return _ParsedHeader(
      name: name,
      value: value,
      nextOffset: valueField.nextOffset,
    );
  }

  static _ParsedField _readField(Uint8List payload, int offset) {
    if (offset + 4 > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final length = _readUint32BigEndian(payload, offset);
    final start = offset + 4;
    final end = start + length;
    if (end > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    return _ParsedField(_ByteSlice(start, end), end);
  }

  static int _skipField(Uint8List payload, int offset) {
    if (offset + 4 > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final length = _readUint32BigEndian(payload, offset);
    final nextOffset = offset + 4 + length;
    if (nextOffset > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    return nextOffset;
  }

  static int _skipHeaderName(Uint8List payload, int offset, bool tokenized) {
    if (!tokenized) {
      return _skipField(payload, offset);
    }
    if (offset + 2 > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final token = (payload[offset] << 8) | payload[offset + 1];
    offset += 2;
    if (token == _bridgeHeaderNameLiteralToken) {
      return _skipField(payload, offset);
    }
    if (token < 0 || token >= _directBridgeHeaderNameTable.length) {
      throw FormatException('invalid bridge header name token: $token');
    }
    return offset;
  }

  /// Locates and validates the body field range.
  _ByteSlice _parseBodyRange() {
    _ensureHeadParsed();
    final headerCount = _headerCount!;
    var offset = _headersOffset!;
    for (var i = 0; i < headerCount; i++) {
      offset = _skipHeaderName(_payload, offset, _tokenizedHeaderNames);
      offset = _skipField(_payload, offset);
    }
    if (offset + 4 > _payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final bodyLength = _readUint32BigEndian(_payload, offset);
    offset += 4;
    final bodyStart = offset;
    final bodyEnd = bodyStart + bodyLength;
    if (bodyEnd > _payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    if (bodyEnd != _payload.length) {
      throw FormatException(
        'unexpected trailing bridge payload bytes: ${_payload.length - bodyEnd}',
      );
    }
    return _ByteSlice(bodyStart, bodyEnd);
  }

  /// Parses fixed request head fields and caches offsets.
  void _ensureHeadParsed() {
    if (_headerCount != null) {
      return;
    }

    var offset = 2;
    final method = _readField(_payload, offset);
    offset = method.nextOffset;
    final scheme = _readField(_payload, offset);
    offset = scheme.nextOffset;
    final authority = _readField(_payload, offset);
    offset = authority.nextOffset;
    final path = _readField(_payload, offset);
    offset = path.nextOffset;
    final query = _readField(_payload, offset);
    offset = query.nextOffset;
    final protocol = _readField(_payload, offset);
    offset = protocol.nextOffset;

    if (offset + 4 > _payload.length) {
      throw const FormatException('truncated bridge payload');
    }

    _methodRange = method.slice;
    _schemeRange = scheme.slice;
    _authorityRange = authority.slice;
    _pathRange = path.slice;
    _queryRange = query.slice;
    _protocolRange = protocol.slice;
    _headerCount = _readUint32BigEndian(_payload, offset);
    _headersOffset = offset + 4;
  }
}

/// Parsed header entry with final cursor offset.
final class _ParsedHeader {
  const _ParsedHeader({
    required this.name,
    required this.value,
    required this.nextOffset,
  });

  final String name;
  final String value;
  final int nextOffset;
}

/// Body stream adapter for a [_DirectPayloadRequestView].
final class _DirectPayloadBodyStream extends Stream<Uint8List> {
  _DirectPayloadBodyStream(this._requestView);

  final _DirectPayloadRequestView _requestView;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final bodyBytes = _requestView.bodyBytes;
    if (bodyBytes.isEmpty) {
      return const Stream<Uint8List>.empty().listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    return Stream<Uint8List>.value(bodyBytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// Read-only header list view over a [BridgeRequestFrame].
final class _DirectHeaderListView extends ListBase<MapEntry<String, String>> {
  _DirectHeaderListView(this._frame);

  final BridgeRequestFrame _frame;

  @override
  int get length => _frame.headerCount;

  @override
  set length(int _) => throw UnsupportedError('unmodifiable');

  @override
  MapEntry<String, String> operator [](int index) =>
      MapEntry(_frame.headerNameAt(index), _frame.headerValueAt(index));

  @override
  void operator []=(int index, MapEntry<String, String> value) =>
      throw UnsupportedError('unmodifiable');
}

/// Fast ASCII case-insensitive equality check.
bool _equalsAsciiIgnoreCase(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    var x = a.codeUnitAt(i);
    var y = b.codeUnitAt(i);
    if (x == y) {
      continue;
    }
    if (x >= 0x41 && x <= 0x5a) {
      x += 0x20;
    }
    if (y >= 0x41 && y <= 0x5a) {
      y += 0x20;
    }
    if (x != y) {
      return false;
    }
  }
  return true;
}
