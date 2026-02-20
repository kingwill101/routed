part of 'bridge_runtime.dart';

/// Reads and validates the common `{version, frameType}` frame header.
int _readAndValidateHeader(
  _BridgeFrameReader reader, {
  required int expectedFrameType,
  required String frameLabel,
}) {
  final version = reader.readUint8();
  if (!_isSupportedBridgeProtocolVersion(version)) {
    throw FormatException('unsupported bridge protocol version: $version');
  }
  final frameType = reader.readUint8();
  if (frameType != expectedFrameType) {
    throw FormatException('invalid bridge $frameLabel frame type: $frameType');
  }
  return frameType;
}

/// Peeks frame type after validating protocol version.
int _peekFrameType(Uint8List payload) {
  if (payload.length < 2) {
    throw const FormatException('truncated bridge payload');
  }
  final version = payload[0];
  if (!_isSupportedBridgeProtocolVersion(version)) {
    throw FormatException('unsupported bridge protocol version: $version');
  }
  return payload[1];
}

/// Returns whether [version] is accepted by the current bridge runtime.
bool _isSupportedBridgeProtocolVersion(int version) {
  return version == bridgeFrameProtocolVersion ||
      version == _bridgeFrameProtocolVersionLegacy;
}

/// Request frame type used for encode operations.
int get _requestFrameTypeForEncode => _encodeTokenizedHeaderFrameTypes
    ? _bridgeRequestFrameTypeTokenized
    : _bridgeRequestFrameType;

/// Request-start frame type used for encode operations.
int get _requestStartFrameTypeForEncode => _encodeTokenizedHeaderFrameTypes
    ? _bridgeRequestStartFrameTypeTokenized
    : _bridgeRequestStartFrameType;

/// Response frame type used for encode operations.
int get _responseFrameTypeForEncode => _bridgeResponseFrameTypeTokenized;

/// Response-start frame type used for encode operations.
int get _responseStartFrameTypeForEncode =>
    _bridgeResponseStartFrameTypeTokenized;

/// Returns whether [frameType] is a valid request payload frame.
bool _isRequestFrameType(int frameType) {
  return frameType == _bridgeRequestFrameType ||
      frameType == _bridgeRequestFrameTypeTokenized;
}

/// Returns whether [frameType] is a tokenized request payload frame.
bool _isTokenizedRequestFrameType(int frameType) {
  return frameType == _bridgeRequestFrameTypeTokenized;
}

/// Returns whether [frameType] is a request-start frame.
bool _isRequestStartFrameType(int frameType) {
  return frameType == _bridgeRequestStartFrameType ||
      frameType == _bridgeRequestStartFrameTypeTokenized;
}

/// Returns whether [frameType] is a tokenized request-start frame.
bool _isTokenizedRequestStartFrameType(int frameType) {
  return frameType == _bridgeRequestStartFrameTypeTokenized;
}

/// Returns whether [frameType] is a valid response payload frame.
bool _isResponseFrameType(int frameType) {
  return frameType == _bridgeResponseFrameType ||
      frameType == _bridgeResponseFrameTypeTokenized;
}

/// Returns whether [frameType] is a tokenized response payload frame.
bool _isTokenizedResponseFrameType(int frameType) {
  return frameType == _bridgeResponseFrameTypeTokenized;
}

/// Returns whether [frameType] is a response-start frame.
bool _isResponseStartFrameType(int frameType) {
  return frameType == _bridgeResponseStartFrameType ||
      frameType == _bridgeResponseStartFrameTypeTokenized;
}

/// Returns whether [frameType] is a tokenized response-start frame.
bool _isTokenizedResponseStartFrameType(int frameType) {
  return frameType == _bridgeResponseStartFrameTypeTokenized;
}

/// Writes a header name either as literal string or compact token.
void _writeHeaderName(
  _BridgeFrameWriter writer,
  String name, {
  required bool tokenized,
}) {
  if (!tokenized) {
    writer.writeString(name);
    return;
  }

  var token = _bridgeHeaderNameToken(name);
  if (token == null) {
    final normalized = _asciiLower(name);
    if (!identical(normalized, name)) {
      token = _bridgeHeaderNameToken(normalized);
    }
  }
  if (token != null) {
    writer.writeUint16(token);
    return;
  }
  writer.writeUint16(_bridgeHeaderNameLiteralToken);
  writer.writeString(name);
}

@pragma('vm:prefer-inline')
/// Returns header token for [name], or `null` when no token is defined.
int? _bridgeHeaderNameToken(String name) {
  switch (name) {
    case 'host':
      return 0;
    case 'connection':
      return 1;
    case 'user-agent':
      return 2;
    case 'accept':
      return 3;
    case 'accept-encoding':
      return 4;
    case 'accept-language':
      return 5;
    case 'content-type':
      return 6;
    case 'content-length':
      return 7;
    case 'transfer-encoding':
      return 8;
    case 'cookie':
      return 9;
    case 'set-cookie':
      return 10;
    case 'cache-control':
      return 11;
    case 'pragma':
      return 12;
    case 'upgrade':
      return 13;
    case 'authorization':
      return 14;
    case 'origin':
      return 15;
    case 'referer':
      return 16;
    case 'location':
      return 17;
    case 'server':
      return 18;
    case 'date':
      return 19;
    case 'x-forwarded-for':
      return 20;
    case 'x-forwarded-proto':
      return 21;
    case 'x-forwarded-host':
      return 22;
    case 'x-forwarded-port':
      return 23;
    case 'x-request-id':
      return 24;
    case 'sec-websocket-key':
      return 25;
    case 'sec-websocket-version':
      return 26;
    case 'sec-websocket-protocol':
      return 27;
    case 'sec-websocket-extensions':
      return 28;
  }
  return null;
}

/// Reads a header name from [reader], resolving tokenized names when enabled.
String _readHeaderName(_BridgeFrameReader reader, {required bool tokenized}) {
  if (!tokenized) {
    return reader.readString();
  }
  final token = reader.readUint16();
  if (token == _bridgeHeaderNameLiteralToken) {
    return reader.readString();
  }
  if (token < 0 || token >= _bridgeHeaderNameTable.length) {
    throw FormatException('invalid bridge header name token: $token');
  }
  return _bridgeHeaderNameTable[token];
}

/// Returns lowercase ASCII representation of [value] without locale semantics.
String _asciiLower(String value) {
  var hasUpper = false;
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code >= 0x41 && code <= 0x5a) {
      hasUpper = true;
      break;
    }
  }
  if (!hasUpper) {
    return value;
  }
  final out = Uint8List(value.length);
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code >= 0x41 && code <= 0x5a) {
      out[i] = code + 0x20;
    } else {
      out[i] = code;
    }
  }
  return String.fromCharCodes(out);
}

/// Normalizes HTTP method to uppercase, defaulting to `GET` when empty.
String _normalizeHttpMethod(String method) {
  if (method.isEmpty) {
    return 'GET';
  }
  for (var i = 0; i < method.length; i++) {
    final code = method.codeUnitAt(i);
    if (code >= 0x61 && code <= 0x7a) {
      return method.toUpperCase();
    }
  }
  return method;
}

/// Growable binary frame writer used by bridge codecs.
final class _BridgeFrameWriter {
  _BridgeFrameWriter([int initialCapacity = 256])
    : _buffer = Uint8List(initialCapacity) {
    _byteData = ByteData.view(_buffer.buffer);
  }

  Uint8List _buffer;
  late ByteData _byteData;
  int _length = 0;

  /// Writes one unsigned byte.
  void writeUint8(int value) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, 'value');
    }
    _ensureCapacity(1);
    _buffer[_length] = value;
    _length += 1;
  }

  /// Writes one big-endian unsigned 16-bit value.
  void writeUint16(int value) {
    if (value < 0 || value > 0xffff) {
      throw RangeError.range(value, 0, 0xffff, 'value');
    }
    _ensureCapacity(2);
    _byteData.setUint16(_length, value, Endian.big);
    _length += 2;
  }

  /// Writes one big-endian unsigned 32-bit value.
  void writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, 'value');
    }
    _ensureCapacity(4);
    _byteData.setUint32(_length, value, Endian.big);
    _length += 4;
  }

  /// Writes a UTF-8 string as `u32 length + bytes`.
  void writeString(String value) {
    if (value.isEmpty) {
      writeUint32(0);
      return;
    }

    var isAscii = true;
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) > 0x7f) {
        isAscii = false;
        break;
      }
    }

    if (isAscii) {
      writeUint32(value.length);
      _ensureCapacity(value.length);
      for (var i = 0; i < value.length; i++) {
        _buffer[_length + i] = value.codeUnitAt(i);
      }
      _length += value.length;
      return;
    }

    writeBytes(utf8.encode(value));
  }

  /// Writes raw bytes as `u32 length + bytes`.
  void writeBytes(List<int> bytes) {
    writeUint32(bytes.length);
    if (bytes.isNotEmpty) {
      _ensureCapacity(bytes.length);
      _buffer.setRange(_length, _length + bytes.length, bytes);
      _length += bytes.length;
    }
  }

  /// Returns encoded bytes view.
  Uint8List takeBytes() => Uint8List.sublistView(_buffer, 0, _length);

  /// Ensures backing buffer can append [additionalBytes].
  void _ensureCapacity(int additionalBytes) {
    final needed = _length + additionalBytes;
    if (needed <= _buffer.length) {
      return;
    }

    var capacity = _buffer.length;
    while (capacity < needed) {
      capacity *= 2;
    }

    final next = Uint8List(capacity);
    next.setRange(0, _length, _buffer);
    _buffer = next;
    _byteData = ByteData.view(next.buffer);
  }
}

/// Binary frame reader used by bridge codecs.
final class _BridgeFrameReader {
  _BridgeFrameReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  /// Reads one unsigned byte.
  int readUint8() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  /// Reads one big-endian unsigned 16-bit value.
  int readUint16() {
    _ensureAvailable(2);
    final value = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return value;
  }

  /// Reads one big-endian unsigned 32-bit value.
  int readUint32() {
    _ensureAvailable(4);
    final value =
        (_bytes[_offset] << 24) |
        (_bytes[_offset + 1] << 16) |
        (_bytes[_offset + 2] << 8) |
        _bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  /// Reads a UTF-8 string encoded as `u32 length + bytes`.
  String readString() {
    final length = readUint32();
    _ensureAvailable(length);
    final start = _offset;
    final end = start + length;
    _offset = end;
    for (var i = start; i < end; i++) {
      if (_bytes[i] > 0x7f) {
        return _strictUtf8Decoder.convert(_bytes, start, end);
      }
    }
    return String.fromCharCodes(_bytes, start, end);
  }

  /// Reads bytes encoded as `u32 length + bytes`.
  Uint8List readBytes() {
    final length = readUint32();
    _ensureAvailable(length);
    final start = _offset;
    _offset += length;
    return Uint8List.sublistView(_bytes, start, start + length);
  }

  /// Validates that all bytes in the payload were consumed.
  void ensureDone() {
    if (_offset != _bytes.length) {
      throw FormatException(
        'unexpected trailing bridge payload bytes: ${_bytes.length - _offset}',
      );
    }
  }

  /// Validates [count] bytes are readable from current cursor.
  void _ensureAvailable(int count) {
    if (_offset + count > _bytes.length) {
      throw const FormatException('truncated bridge payload');
    }
  }
}
