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

  void forEachMatchingHeader(String name, void Function(String value) visitor);

  String? firstHeaderValue(String name);
}

final class _BridgeRequestMetadata {
  const _BridgeRequestMetadata({
    required this.contentLength,
    required this.persistentConnection,
    required this.chunkedTransferEncoding,
    required this.hasMultipleConnectionHeaders,
    this.hostHeader,
    this.forwardedProto,
    this.forwardedHost,
    this.connectionHeaderValue,
    this.payloadBodyRange,
  });

  final int contentLength;
  final bool persistentConnection;
  final bool chunkedTransferEncoding;
  final bool hasMultipleConnectionHeaders;
  final String? hostHeader;
  final String? forwardedProto;
  final String? forwardedHost;
  final String? connectionHeaderValue;
  final _BridgeByteSlice? payloadBodyRange;
}

_BridgeRequestMetadata _bridgeRequestMetadataFromSource(
  _BridgeRequestSource source,
) {
  return switch (source) {
    _BridgePayloadRequestSource payload => payload.metadata,
    _ => _scanBridgeRequestMetadata(source),
  };
}

_BridgeRequestMetadata _scanBridgeRequestMetadata(_BridgeRequestSource source) {
  final defaultPersistentConnection = _defaultPersistentConnectionForProtocol(
    source.protocol,
  );
  var hasClose = false;
  var hasKeepAlive = false;
  var hasChunkedTransferEncoding = false;
  var hasMultipleConnectionHeaders = false;
  var sawContentLength = false;
  var contentLength = -1;
  String? hostHeader;
  String? forwardedProto;
  String? forwardedHost;
  String? connectionHeaderValue;

  source.forEachHeader((name, value) {
    if (hostHeader == null &&
        _equalsAsciiIgnoreCase(name, HttpHeaders.hostHeader)) {
      hostHeader = value.trim();
      return;
    }
    if (forwardedProto == null &&
        _equalsAsciiIgnoreCase(name, 'x-forwarded-proto')) {
      forwardedProto = value.trim();
      return;
    }
    if (forwardedHost == null &&
        _equalsAsciiIgnoreCase(name, 'x-forwarded-host')) {
      forwardedHost = value.trim();
      return;
    }
    if (!sawContentLength &&
        _equalsAsciiIgnoreCase(name, HttpHeaders.contentLengthHeader)) {
      sawContentLength = true;
      contentLength = int.tryParse(value.trim()) ?? -1;
      return;
    }
    if (_equalsAsciiIgnoreCase(name, HttpHeaders.transferEncodingHeader)) {
      hasChunkedTransferEncoding =
          hasChunkedTransferEncoding ||
          _headerValueContainsTokenIgnoreCase(value, 'chunked');
      return;
    }
    if (!_equalsAsciiIgnoreCase(name, HttpHeaders.connectionHeader)) {
      return;
    }
    if (connectionHeaderValue == null) {
      connectionHeaderValue = value;
    } else {
      hasMultipleConnectionHeaders = true;
    }
    (
      hasClose: hasClose,
      hasKeepAlive: hasKeepAlive,
    ) = _scanBridgeConnectionHeaderValue(
      value,
      hasClose: hasClose,
      hasKeepAlive: hasKeepAlive,
    );
  });

  return _BridgeRequestMetadata(
    contentLength: contentLength,
    persistentConnection: hasClose
        ? false
        : hasKeepAlive
        ? true
        : defaultPersistentConnection,
    chunkedTransferEncoding: hasChunkedTransferEncoding,
    hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
    hostHeader: hostHeader,
    forwardedProto: forwardedProto,
    forwardedHost: forwardedHost,
    connectionHeaderValue: connectionHeaderValue,
  );
}

@pragma('vm:prefer-inline')
bool _defaultPersistentConnectionForProtocol(String protocol) {
  return switch (protocol.trim().toLowerCase()) {
    '1.0' || 'http/1.0' => false,
    _ => true,
  };
}

({bool hasClose, bool hasKeepAlive}) _scanBridgeConnectionHeaderValue(
  String value, {
  required bool hasClose,
  required bool hasKeepAlive,
}) {
  var nextHasClose = hasClose;
  var nextHasKeepAlive = hasKeepAlive;
  var partStart = 0;
  while (partStart <= value.length) {
    var partEnd = partStart;
    while (partEnd < value.length && value.codeUnitAt(partEnd) != 0x2c) {
      partEnd++;
    }
    final start = _skipHttpTokenWhitespace(value, partStart, partEnd);
    final end = _trimHttpTokenWhitespace(value, start, partEnd);
    if (end > start &&
        _equalsAsciiIgnoreCaseRange(value, start, end, 'close')) {
      nextHasClose = true;
    } else if (end > start &&
        _equalsAsciiIgnoreCaseRange(value, start, end, 'keep-alive')) {
      nextHasKeepAlive = true;
    }
    if (partEnd == value.length) {
      break;
    }
    partStart = partEnd + 1;
  }
  return (hasClose: nextHasClose, hasKeepAlive: nextHasKeepAlive);
}

@pragma('vm:prefer-inline')
int? _bridgeHeaderLookupTokenIgnoreCase(String name) {
  final exact = _bridgeHeaderLookupToken(name);
  if (exact != null) {
    return exact;
  }
  for (var i = 0; i < _bridgeHeaderNameTable.length; i++) {
    if (_equalsAsciiIgnoreCase(_bridgeHeaderNameTable[i], name)) {
      return i;
    }
  }
  return null;
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
  void forEachMatchingHeader(String name, void Function(String value) visitor) {
    for (var i = 0; i < _frame.headerCount; i++) {
      final headerName = _frame.headerNameAt(i);
      if (_equalsAsciiIgnoreCase(headerName, name)) {
        visitor(_frame.headerValueAt(i));
      }
    }
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
  _BridgeRequestMetadata? _metadata;

  _BridgeRequestMetadata get metadata => _metadata ??= _scanMetadata();

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
    final range = _bodyRange ??= metadata.payloadBodyRange!;
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
  void forEachMatchingHeader(String name, void Function(String value) visitor) {
    _ensureHeadParsed();
    final tokenLookup = _tokenizedHeaderNames
        ? _bridgeHeaderLookupTokenIgnoreCase(name)
        : null;
    var offset = _headersOffset!;
    for (var i = 0; i < _headerCount!; i++) {
      var matches = false;
      if (!_tokenizedHeaderNames) {
        final nameField = _readField(_payload, offset);
        matches = _equalsAsciiIgnoreCase(
          _readFieldString(nameField.slice),
          name,
        );
        offset = nameField.nextOffset;
      } else {
        if (offset + 2 > _payload.length) {
          throw const FormatException('truncated bridge payload');
        }
        final token = (_payload[offset] << 8) | _payload[offset + 1];
        offset += 2;
        if (token == _bridgeHeaderNameLiteralToken) {
          final nameField = _readField(_payload, offset);
          matches = _equalsAsciiIgnoreCase(
            _readFieldString(nameField.slice),
            name,
          );
          offset = nameField.nextOffset;
        } else {
          if (token < 0 || token >= _bridgeHeaderNameTable.length) {
            throw FormatException('invalid bridge header name token: $token');
          }
          matches = tokenLookup != null && token == tokenLookup;
        }
      }

      final valueField = _readField(_payload, offset);
      if (matches) {
        visitor(_readFieldString(valueField.slice));
      }
      offset = valueField.nextOffset;
    }
  }

  @override
  String? firstHeaderValue(String name) {
    _ensureHeadParsed();
    final tokenLookup = _tokenizedHeaderNames
        ? _bridgeHeaderLookupTokenIgnoreCase(name)
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

  _BridgeByteSlice _readPayloadBodyRange(int offset) {
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

  _BridgeRequestMetadata _scanMetadata() {
    _ensureHeadParsed();
    final defaultPersistentConnection = _defaultPersistentConnectionForProtocol(
      protocol,
    );
    var hasClose = false;
    var hasKeepAlive = false;
    var hasChunkedTransferEncoding = false;
    var hasMultipleConnectionHeaders = false;
    var sawContentLength = false;
    var contentLength = -1;
    String? hostHeader;
    String? forwardedProto;
    String? forwardedHost;
    String? connectionHeaderValue;

    var offset = _headersOffset!;
    for (var i = 0; i < _headerCount!; i++) {
      if (_tokenizedHeaderNames) {
        if (offset + 2 > _payload.length) {
          throw const FormatException('truncated bridge payload');
        }
        final token = (_payload[offset] << 8) | _payload[offset + 1];
        offset += 2;
        if (token == _bridgeHeaderNameLiteralToken) {
          final nameField = _readField(_payload, offset);
          final name = _readFieldString(nameField.slice);
          offset = nameField.nextOffset;
          final scanned = _scanLiteralMetadataHeader(
            name,
            offset,
            hasClose: hasClose,
            hasKeepAlive: hasKeepAlive,
            hasChunkedTransferEncoding: hasChunkedTransferEncoding,
            hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
            sawContentLength: sawContentLength,
            contentLength: contentLength,
            hostHeader: hostHeader,
            forwardedProto: forwardedProto,
            forwardedHost: forwardedHost,
            connectionHeaderValue: connectionHeaderValue,
          );
          offset = scanned.nextOffset;
          hasClose = scanned.hasClose;
          hasKeepAlive = scanned.hasKeepAlive;
          hasChunkedTransferEncoding = scanned.hasChunkedTransferEncoding;
          hasMultipleConnectionHeaders = scanned.hasMultipleConnectionHeaders;
          sawContentLength = scanned.sawContentLength;
          contentLength = scanned.contentLength;
          hostHeader = scanned.hostHeader;
          forwardedProto = scanned.forwardedProto;
          forwardedHost = scanned.forwardedHost;
          connectionHeaderValue = scanned.connectionHeaderValue;
          continue;
        }
        if (token < 0 || token >= _bridgeHeaderNameTable.length) {
          throw FormatException('invalid bridge header name token: $token');
        }
        final scanned = _scanTokenizedMetadataHeader(
          token,
          offset,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: hostHeader,
          forwardedProto: forwardedProto,
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue,
        );
        offset = scanned.nextOffset;
        hasClose = scanned.hasClose;
        hasKeepAlive = scanned.hasKeepAlive;
        hasChunkedTransferEncoding = scanned.hasChunkedTransferEncoding;
        hasMultipleConnectionHeaders = scanned.hasMultipleConnectionHeaders;
        sawContentLength = scanned.sawContentLength;
        contentLength = scanned.contentLength;
        hostHeader = scanned.hostHeader;
        forwardedProto = scanned.forwardedProto;
        forwardedHost = scanned.forwardedHost;
        connectionHeaderValue = scanned.connectionHeaderValue;
        continue;
      }

      final nameField = _readField(_payload, offset);
      final name = _readFieldString(nameField.slice);
      offset = nameField.nextOffset;
      final scanned = _scanLiteralMetadataHeader(
        name,
        offset,
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding: hasChunkedTransferEncoding,
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: sawContentLength,
        contentLength: contentLength,
        hostHeader: hostHeader,
        forwardedProto: forwardedProto,
        forwardedHost: forwardedHost,
        connectionHeaderValue: connectionHeaderValue,
      );
      offset = scanned.nextOffset;
      hasClose = scanned.hasClose;
      hasKeepAlive = scanned.hasKeepAlive;
      hasChunkedTransferEncoding = scanned.hasChunkedTransferEncoding;
      hasMultipleConnectionHeaders = scanned.hasMultipleConnectionHeaders;
      sawContentLength = scanned.sawContentLength;
      contentLength = scanned.contentLength;
      hostHeader = scanned.hostHeader;
      forwardedProto = scanned.forwardedProto;
      forwardedHost = scanned.forwardedHost;
      connectionHeaderValue = scanned.connectionHeaderValue;
    }

    final bodyRange = _readPayloadBodyRange(offset);
    _bodyRange = bodyRange;
    return _BridgeRequestMetadata(
      contentLength: contentLength,
      persistentConnection: hasClose
          ? false
          : hasKeepAlive
          ? true
          : defaultPersistentConnection,
      chunkedTransferEncoding: hasChunkedTransferEncoding,
      hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
      hostHeader: hostHeader,
      forwardedProto: forwardedProto,
      forwardedHost: forwardedHost,
      connectionHeaderValue: connectionHeaderValue,
      payloadBodyRange: bodyRange,
    );
  }

  _ScannedBridgeMetadataHeader _scanLiteralMetadataHeader(
    String name,
    int offset, {
    required bool hasClose,
    required bool hasKeepAlive,
    required bool hasChunkedTransferEncoding,
    required bool hasMultipleConnectionHeaders,
    required bool sawContentLength,
    required int contentLength,
    required String? hostHeader,
    required String? forwardedProto,
    required String? forwardedHost,
    required String? connectionHeaderValue,
  }) {
    if (hostHeader == null &&
        _equalsAsciiIgnoreCase(name, HttpHeaders.hostHeader)) {
      final valueField = _readField(_payload, offset);
      return _ScannedBridgeMetadataHeader(
        nextOffset: valueField.nextOffset,
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding: hasChunkedTransferEncoding,
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: sawContentLength,
        contentLength: contentLength,
        hostHeader: _readFieldString(valueField.slice).trim(),
        forwardedProto: forwardedProto,
        forwardedHost: forwardedHost,
        connectionHeaderValue: connectionHeaderValue,
      );
    }
    if (forwardedProto == null &&
        _equalsAsciiIgnoreCase(name, 'x-forwarded-proto')) {
      final valueField = _readField(_payload, offset);
      return _ScannedBridgeMetadataHeader(
        nextOffset: valueField.nextOffset,
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding: hasChunkedTransferEncoding,
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: sawContentLength,
        contentLength: contentLength,
        hostHeader: hostHeader,
        forwardedProto: _readFieldString(valueField.slice).trim(),
        forwardedHost: forwardedHost,
        connectionHeaderValue: connectionHeaderValue,
      );
    }
    if (forwardedHost == null &&
        _equalsAsciiIgnoreCase(name, 'x-forwarded-host')) {
      final valueField = _readField(_payload, offset);
      return _ScannedBridgeMetadataHeader(
        nextOffset: valueField.nextOffset,
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding: hasChunkedTransferEncoding,
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: sawContentLength,
        contentLength: contentLength,
        hostHeader: hostHeader,
        forwardedProto: forwardedProto,
        forwardedHost: _readFieldString(valueField.slice).trim(),
        connectionHeaderValue: connectionHeaderValue,
      );
    }
    if (!sawContentLength &&
        _equalsAsciiIgnoreCase(name, HttpHeaders.contentLengthHeader)) {
      final valueField = _readField(_payload, offset);
      final value = _readFieldString(valueField.slice);
      return _ScannedBridgeMetadataHeader(
        nextOffset: valueField.nextOffset,
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding: hasChunkedTransferEncoding,
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: true,
        contentLength: int.tryParse(value.trim()) ?? -1,
        hostHeader: hostHeader,
        forwardedProto: forwardedProto,
        forwardedHost: forwardedHost,
        connectionHeaderValue: connectionHeaderValue,
      );
    }
    if (_equalsAsciiIgnoreCase(name, HttpHeaders.transferEncodingHeader)) {
      final valueField = _readField(_payload, offset);
      return _ScannedBridgeMetadataHeader(
        nextOffset: valueField.nextOffset,
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding:
            hasChunkedTransferEncoding ||
            _headerValueContainsTokenIgnoreCase(
              _readFieldString(valueField.slice),
              'chunked',
            ),
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: sawContentLength,
        contentLength: contentLength,
        hostHeader: hostHeader,
        forwardedProto: forwardedProto,
        forwardedHost: forwardedHost,
        connectionHeaderValue: connectionHeaderValue,
      );
    }
    if (!_equalsAsciiIgnoreCase(name, HttpHeaders.connectionHeader)) {
      return _ScannedBridgeMetadataHeader(
        nextOffset: _skipField(_payload, offset),
        hasClose: hasClose,
        hasKeepAlive: hasKeepAlive,
        hasChunkedTransferEncoding: hasChunkedTransferEncoding,
        hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
        sawContentLength: sawContentLength,
        contentLength: contentLength,
        hostHeader: hostHeader,
        forwardedProto: forwardedProto,
        forwardedHost: forwardedHost,
        connectionHeaderValue: connectionHeaderValue,
      );
    }

    final valueField = _readField(_payload, offset);
    final rawValue = _readFieldString(valueField.slice);
    final scannedConnection = _scanBridgeConnectionHeaderValue(
      rawValue,
      hasClose: hasClose,
      hasKeepAlive: hasKeepAlive,
    );
    return _ScannedBridgeMetadataHeader(
      nextOffset: valueField.nextOffset,
      hasClose: scannedConnection.hasClose,
      hasKeepAlive: scannedConnection.hasKeepAlive,
      hasChunkedTransferEncoding: hasChunkedTransferEncoding,
      hasMultipleConnectionHeaders:
          hasMultipleConnectionHeaders || connectionHeaderValue != null,
      sawContentLength: sawContentLength,
      contentLength: contentLength,
      hostHeader: hostHeader,
      forwardedProto: forwardedProto,
      forwardedHost: forwardedHost,
      connectionHeaderValue: connectionHeaderValue ?? rawValue,
    );
  }

  _ScannedBridgeMetadataHeader _scanTokenizedMetadataHeader(
    int token,
    int offset, {
    required bool hasClose,
    required bool hasKeepAlive,
    required bool hasChunkedTransferEncoding,
    required bool hasMultipleConnectionHeaders,
    required bool sawContentLength,
    required int contentLength,
    required String? hostHeader,
    required String? forwardedProto,
    required String? forwardedHost,
    required String? connectionHeaderValue,
  }) {
    switch (token) {
      case 0 when hostHeader == null:
        final valueField = _readField(_payload, offset);
        return _ScannedBridgeMetadataHeader(
          nextOffset: valueField.nextOffset,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: _readFieldString(valueField.slice).trim(),
          forwardedProto: forwardedProto,
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue,
        );
      case 1:
        final valueField = _readField(_payload, offset);
        final rawValue = _readFieldString(valueField.slice);
        final scannedConnection = _scanBridgeConnectionHeaderValue(
          rawValue,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
        );
        return _ScannedBridgeMetadataHeader(
          nextOffset: valueField.nextOffset,
          hasClose: scannedConnection.hasClose,
          hasKeepAlive: scannedConnection.hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders:
              hasMultipleConnectionHeaders || connectionHeaderValue != null,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: hostHeader,
          forwardedProto: forwardedProto,
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue ?? rawValue,
        );
      case 8:
        final valueField = _readField(_payload, offset);
        return _ScannedBridgeMetadataHeader(
          nextOffset: valueField.nextOffset,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding:
              hasChunkedTransferEncoding ||
              _headerValueContainsTokenIgnoreCase(
                _readFieldString(valueField.slice),
                'chunked',
              ),
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: hostHeader,
          forwardedProto: forwardedProto,
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue,
        );
      case 7 when !sawContentLength:
        final valueField = _readField(_payload, offset);
        final value = _readFieldString(valueField.slice);
        return _ScannedBridgeMetadataHeader(
          nextOffset: valueField.nextOffset,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: true,
          contentLength: int.tryParse(value.trim()) ?? -1,
          hostHeader: hostHeader,
          forwardedProto: forwardedProto,
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue,
        );
      case 21 when forwardedProto == null:
        final valueField = _readField(_payload, offset);
        return _ScannedBridgeMetadataHeader(
          nextOffset: valueField.nextOffset,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: hostHeader,
          forwardedProto: _readFieldString(valueField.slice).trim(),
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue,
        );
      case 22 when forwardedHost == null:
        final valueField = _readField(_payload, offset);
        return _ScannedBridgeMetadataHeader(
          nextOffset: valueField.nextOffset,
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: hostHeader,
          forwardedProto: forwardedProto,
          forwardedHost: _readFieldString(valueField.slice).trim(),
          connectionHeaderValue: connectionHeaderValue,
        );
      default:
        return _ScannedBridgeMetadataHeader(
          nextOffset: _skipField(_payload, offset),
          hasClose: hasClose,
          hasKeepAlive: hasKeepAlive,
          hasChunkedTransferEncoding: hasChunkedTransferEncoding,
          hasMultipleConnectionHeaders: hasMultipleConnectionHeaders,
          sawContentLength: sawContentLength,
          contentLength: contentLength,
          hostHeader: hostHeader,
          forwardedProto: forwardedProto,
          forwardedHost: forwardedHost,
          connectionHeaderValue: connectionHeaderValue,
        );
    }
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

final class _ScannedBridgeMetadataHeader {
  const _ScannedBridgeMetadataHeader({
    required this.nextOffset,
    required this.hasClose,
    required this.hasKeepAlive,
    required this.hasChunkedTransferEncoding,
    required this.hasMultipleConnectionHeaders,
    required this.sawContentLength,
    required this.contentLength,
    required this.hostHeader,
    required this.forwardedProto,
    required this.forwardedHost,
    required this.connectionHeaderValue,
  });

  final int nextOffset;
  final bool hasClose;
  final bool hasKeepAlive;
  final bool hasChunkedTransferEncoding;
  final bool hasMultipleConnectionHeaders;
  final bool sawContentLength;
  final int contentLength;
  final String? hostHeader;
  final String? forwardedProto;
  final String? forwardedHost;
  final String? connectionHeaderValue;
}

@pragma('vm:prefer-inline')
int _readBridgeUint32BigEndian(Uint8List buffer, int offset) {
  return (buffer[offset] << 24) |
      (buffer[offset + 1] << 16) |
      (buffer[offset + 2] << 8) |
      buffer[offset + 3];
}
