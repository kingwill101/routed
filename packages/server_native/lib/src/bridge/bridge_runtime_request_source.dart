part of 'bridge_runtime.dart';

abstract interface class _BridgeRequestSource {
  String get method;
  String get scheme;
  String get authority;
  String get path;
  String get query;
  String get protocol;
  Uint8List get bodyBytes;

  void forEachHeader(void Function(String name, String value) visitor);

  String? firstHeaderValue(String name);
}

final class _BridgeFrameRequestSource implements _BridgeRequestSource {
  _BridgeFrameRequestSource(this._frame);

  final BridgeRequestFrame _frame;

  @override
  String get method => _frame.method;

  @override
  String get scheme => _frame.scheme;

  @override
  String get authority => _frame.authority;

  @override
  String get path => _frame.path;

  @override
  String get query => _frame.query;

  @override
  String get protocol => _frame.protocol;

  @override
  Uint8List get bodyBytes => _frame.bodyBytes;

  @override
  void forEachHeader(void Function(String name, String value) visitor) {
    _frame.forEachHeader(visitor);
  }

  @override
  String? firstHeaderValue(String name) {
    for (var i = 0; i < _frame.headerCount; i++) {
      final headerName = _frame.headerNameAt(i);
      if (_equalsAsciiIgnoreCase(headerName, name)) {
        return _frame.headerValueAt(i);
      }
    }
    return null;
  }
}

/// Non-owning byte range into a bridge payload.
final class _BridgeByteSlice {
  const _BridgeByteSlice(this.start, this.end);

  final int start;
  final int end;
}

/// Decoded field metadata (`slice + next offset`).
final class _BridgeParsedField {
  const _BridgeParsedField(this.slice, this.nextOffset);

  final _BridgeByteSlice slice;
  final int nextOffset;
}

final class _BridgePayloadRequestSource implements _BridgeRequestSource {
  _BridgePayloadRequestSource._({
    required Uint8List payload,
    required bool tokenizedHeaderNames,
  }) : _payload = payload,
       _tokenizedHeaderNames = tokenizedHeaderNames;

  factory _BridgePayloadRequestSource.parse(Uint8List payload) {
    if (payload.length < 2) {
      throw const FormatException('truncated bridge payload');
    }
    final version = payload[0];
    if (!_isSupportedBridgeProtocolVersion(version)) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = payload[1];
    if (!_isRequestFrameType(frameType)) {
      throw FormatException('invalid bridge request frame type: $frameType');
    }
    return _BridgePayloadRequestSource._(
      payload: payload,
      tokenizedHeaderNames: _isTokenizedRequestFrameType(frameType),
    );
  }

  final Uint8List _payload;
  final bool _tokenizedHeaderNames;
  _BridgeByteSlice? _methodRange;
  _BridgeByteSlice? _schemeRange;
  _BridgeByteSlice? _authorityRange;
  _BridgeByteSlice? _pathRange;
  _BridgeByteSlice? _queryRange;
  _BridgeByteSlice? _protocolRange;
  int? _headerCount;
  int? _headersOffset;

  String? _method;
  String? _scheme;
  String? _authority;
  String? _path;
  String? _query;
  String? _protocol;
  _BridgeByteSlice? _bodyRange;
  Uint8List? _bodyBytes;

  @override
  String get method {
    _ensureHeadParsed();
    return _method ??= _normalizeHttpMethod(_readFieldString(_methodRange!));
  }

  @override
  String get scheme {
    _ensureHeadParsed();
    return _scheme ??= _readFieldOrDefault(_schemeRange!, 'http');
  }

  @override
  String get authority {
    _ensureHeadParsed();
    return _authority ??= _readFieldOrDefault(_authorityRange!, '127.0.0.1');
  }

  @override
  String get path {
    _ensureHeadParsed();
    return _path ??= _readFieldOrDefault(_pathRange!, '/');
  }

  @override
  String get query {
    _ensureHeadParsed();
    return _query ??= _readFieldString(_queryRange!);
  }

  @override
  String get protocol {
    _ensureHeadParsed();
    return _protocol ??= _readFieldOrDefault(_protocolRange!, '1.1');
  }

  @override
  Uint8List get bodyBytes {
    final range = _bodyRange ??= _parseBodyRange();
    return _bodyBytes ??= Uint8List.sublistView(
      _payload,
      range.start,
      range.end,
    );
  }

  @override
  void forEachHeader(void Function(String name, String value) visitor) {
    _ensureHeadParsed();
    var offset = _headersOffset!;
    for (var i = 0; i < _headerCount!; i++) {
      final parsed = _readHeaderAt(offset);
      visitor(parsed.name, parsed.value);
      offset = parsed.nextOffset;
    }
  }

  @override
  String? firstHeaderValue(String name) {
    _ensureHeadParsed();
    final tokenLookup = _tokenizedHeaderNames
        ? _bridgeHeaderLookupToken(name)
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
        if (token < 0 || token >= _bridgeHeaderNameTable.length) {
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

  String _readFieldOrDefault(_BridgeByteSlice range, String fallback) {
    if (range.start == range.end) {
      return fallback;
    }
    return _readFieldString(range);
  }

  @pragma('vm:prefer-inline')
  String _readFieldString(_BridgeByteSlice range) {
    for (var i = range.start; i < range.end; i++) {
      if (_payload[i] > 0x7f) {
        return _strictUtf8Decoder.convert(_payload, range.start, range.end);
      }
    }
    return String.fromCharCodes(_payload, range.start, range.end);
  }

  _BridgeParsedHeader _readHeaderAt(int offset) {
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
        if (token < 0 || token >= _bridgeHeaderNameTable.length) {
          throw FormatException('invalid bridge header name token: $token');
        }
        name = _bridgeHeaderNameTable[token];
      }
    }

    final valueField = _readField(_payload, offset);
    return _BridgeParsedHeader(
      name: name,
      value: _readFieldString(valueField.slice),
      nextOffset: valueField.nextOffset,
    );
  }

  static _BridgeParsedField _readField(Uint8List payload, int offset) {
    if (offset + 4 > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final length = _readBridgeUint32BigEndian(payload, offset);
    final start = offset + 4;
    final end = start + length;
    if (end > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    return _BridgeParsedField(_BridgeByteSlice(start, end), end);
  }

  static int _skipField(Uint8List payload, int offset) {
    if (offset + 4 > payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final length = _readBridgeUint32BigEndian(payload, offset);
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
    if (token < 0 || token >= _bridgeHeaderNameTable.length) {
      throw FormatException('invalid bridge header name token: $token');
    }
    return offset;
  }

  _BridgeByteSlice _parseBodyRange() {
    _ensureHeadParsed();
    var offset = _headersOffset!;
    for (var i = 0; i < _headerCount!; i++) {
      offset = _skipHeaderName(_payload, offset, _tokenizedHeaderNames);
      offset = _skipField(_payload, offset);
    }
    if (offset + 4 > _payload.length) {
      throw const FormatException('truncated bridge payload');
    }
    final bodyLength = _readBridgeUint32BigEndian(_payload, offset);
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
    return _BridgeByteSlice(bodyStart, bodyEnd);
  }

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
    _headerCount = _readBridgeUint32BigEndian(_payload, offset);
    _headersOffset = offset + 4;
  }
}

final class _BridgeParsedHeader {
  const _BridgeParsedHeader({
    required this.name,
    required this.value,
    required this.nextOffset,
  });

  final String name;
  final String value;
  final int nextOffset;
}

@pragma('vm:prefer-inline')
int _readBridgeUint32BigEndian(Uint8List buffer, int offset) {
  return (buffer[offset] << 24) |
      (buffer[offset + 1] << 16) |
      (buffer[offset + 2] << 8) |
      buffer[offset + 3];
}
