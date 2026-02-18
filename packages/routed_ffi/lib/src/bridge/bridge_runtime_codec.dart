part of 'bridge_runtime.dart';

/// Current bridge wire protocol version.
const int bridgeFrameProtocolVersion = 1;
const int _bridgeRequestFrameType = 1; // legacy single-frame request
const int _bridgeResponseFrameType = 2; // legacy single-frame response
const int _bridgeRequestStartFrameType = 3;
const int _bridgeRequestChunkFrameType = 4;
const int _bridgeRequestEndFrameType = 5;
const int _bridgeResponseStartFrameType = 6;
const int _bridgeResponseChunkFrameType = 7;
const int _bridgeResponseEndFrameType = 8;
const int _bridgeTunnelChunkFrameType = 9;
const int _bridgeTunnelCloseFrameType = 10;
const Utf8Decoder _strictUtf8Decoder = Utf8Decoder(allowMalformed: false);

/// A binary bridge request frame passed from Rust transport to Dart.
///
/// {@macro routed_ffi_bridge_protocol_overview}
///
/// {@macro routed_ffi_bridge_request_example}
final class BridgeRequestFrame {
  BridgeRequestFrame({
    required this.method,
    required this.scheme,
    required this.authority,
    required this.path,
    required this.query,
    required this.protocol,
    required List<MapEntry<String, String>> headers,
    required this.bodyBytes,
  }) : _headers = headers,
       _headerNames = null,
       _headerValues = null;

  BridgeRequestFrame._decoded({
    required this.method,
    required this.scheme,
    required this.authority,
    required this.path,
    required this.query,
    required this.protocol,
    required List<String> headerNames,
    required List<String> headerValues,
    required this.bodyBytes,
  }) : _headers = null,
       _headerNames = headerNames,
       _headerValues = headerValues;

  final String method;
  final String scheme;
  final String authority;
  final String path;
  final String query;
  final String protocol;
  final Uint8List bodyBytes;
  List<MapEntry<String, String>>? _headers;
  final List<String>? _headerNames;
  final List<String>? _headerValues;

  List<MapEntry<String, String>> get headers =>
      _headers ??= _materializeHeaders();

  int get headerCount => _headerNames?.length ?? _headers?.length ?? 0;

  String headerNameAt(int index) {
    final names = _headerNames;
    if (names != null) {
      return names[index];
    }
    return _headers![index].key;
  }

  String headerValueAt(int index) {
    final values = _headerValues;
    if (values != null) {
      return values[index];
    }
    return _headers![index].value;
  }

  void forEachHeader(void Function(String name, String value) visitor) {
    final names = _headerNames;
    if (names != null) {
      final values = _headerValues!;
      for (var i = 0; i < names.length; i++) {
        visitor(names[i], values[i]);
      }
      return;
    }
    final headers = _headers;
    if (headers == null) {
      return;
    }
    for (final entry in headers) {
      visitor(entry.key, entry.value);
    }
  }

  List<MapEntry<String, String>> _materializeHeaders() {
    final names = _headerNames;
    if (names == null || names.isEmpty) {
      return const <MapEntry<String, String>>[];
    }
    final values = _headerValues!;
    return List<MapEntry<String, String>>.generate(
      names.length,
      (i) => MapEntry(names[i], values[i]),
      growable: false,
    );
  }

  BridgeRequestFrame copyWith({
    String? method,
    String? scheme,
    String? authority,
    String? path,
    String? query,
    String? protocol,
    List<MapEntry<String, String>>? headers,
    Uint8List? bodyBytes,
  }) {
    return BridgeRequestFrame(
      method: method ?? this.method,
      scheme: scheme ?? this.scheme,
      authority: authority ?? this.authority,
      path: path ?? this.path,
      query: query ?? this.query,
      protocol: protocol ?? this.protocol,
      headers: headers ?? this.headers,
      bodyBytes: bodyBytes ?? this.bodyBytes,
    );
  }

  Uint8List encodePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeRequestFrameType);
    writer.writeString(method);
    writer.writeString(scheme);
    writer.writeString(authority);
    writer.writeString(path);
    writer.writeString(query);
    writer.writeString(protocol);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      writer.writeString(headerNameAt(i));
      writer.writeString(headerValueAt(i));
    }
    writer.writeBytes(bodyBytes);
    return writer.takeBytes();
  }

  factory BridgeRequestFrame.decodePayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final version = reader.readUint8();
    if (version != bridgeFrameProtocolVersion) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = reader.readUint8();
    if (frameType != _bridgeRequestFrameType) {
      throw FormatException('invalid bridge request frame type: $frameType');
    }

    final method = _normalizeHttpMethod(reader.readString());
    final scheme = reader.readString();
    final authority = reader.readString();
    final path = reader.readString();
    final query = reader.readString();
    final protocol = reader.readString();
    final headerCount = reader.readUint32();
    final headerNames = List<String>.filled(headerCount, '', growable: false);
    final headerValues = List<String>.filled(headerCount, '', growable: false);
    for (var i = 0; i < headerCount; i++) {
      headerNames[i] = reader.readString();
      headerValues[i] = reader.readString();
    }
    final bodyBytes = reader.readBytes();
    reader.ensureDone();
    return BridgeRequestFrame._decoded(
      method: method.isEmpty ? 'GET' : method,
      scheme: scheme.isEmpty ? 'http' : scheme,
      authority: authority.isEmpty ? '127.0.0.1' : authority,
      path: path.isEmpty ? '/' : path,
      query: query,
      protocol: protocol.isEmpty ? '1.1' : protocol,
      headerNames: headerNames,
      headerValues: headerValues,
      bodyBytes: bodyBytes,
    );
  }

  Uint8List encodeStartPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeRequestStartFrameType);
    writer.writeString(method);
    writer.writeString(scheme);
    writer.writeString(authority);
    writer.writeString(path);
    writer.writeString(query);
    writer.writeString(protocol);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      writer.writeString(headerNameAt(i));
      writer.writeString(headerValueAt(i));
    }
    return writer.takeBytes();
  }

  factory BridgeRequestFrame.decodeStartPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final frameType = _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeRequestStartFrameType,
      frameLabel: 'request start',
    );
    if (frameType != _bridgeRequestStartFrameType) {
      throw StateError('unreachable');
    }
    final method = _normalizeHttpMethod(reader.readString());
    final scheme = reader.readString();
    final authority = reader.readString();
    final path = reader.readString();
    final query = reader.readString();
    final protocol = reader.readString();
    final headerCount = reader.readUint32();
    final headerNames = List<String>.filled(headerCount, '', growable: false);
    final headerValues = List<String>.filled(headerCount, '', growable: false);
    for (var i = 0; i < headerCount; i++) {
      headerNames[i] = reader.readString();
      headerValues[i] = reader.readString();
    }
    reader.ensureDone();
    return BridgeRequestFrame._decoded(
      method: method.isEmpty ? 'GET' : method,
      scheme: scheme.isEmpty ? 'http' : scheme,
      authority: authority.isEmpty ? '127.0.0.1' : authority,
      path: path.isEmpty ? '/' : path,
      query: query,
      protocol: protocol.isEmpty ? '1.1' : protocol,
      headerNames: headerNames,
      headerValues: headerValues,
      bodyBytes: Uint8List(0),
    );
  }

  static Uint8List encodeChunkPayload(List<int> chunkBytes) {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeRequestChunkFrameType);
    writer.writeBytes(chunkBytes);
    return writer.takeBytes();
  }

  static Uint8List decodeChunkPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeRequestChunkFrameType,
      frameLabel: 'request chunk',
    );
    final chunk = reader.readBytes();
    reader.ensureDone();
    return chunk;
  }

  static Uint8List encodeEndPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeRequestEndFrameType);
    return writer.takeBytes();
  }

  static void decodeEndPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeRequestEndFrameType,
      frameLabel: 'request end',
    );
    reader.ensureDone();
  }

  static bool isChunkPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeRequestChunkFrameType;
  }

  static bool isEndPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeRequestEndFrameType;
  }

  static bool isStartPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeRequestStartFrameType;
  }
}

/// A binary bridge response frame passed from Dart handlers back to Rust.
///
/// {@macro routed_ffi_bridge_protocol_overview}
///
/// {@macro routed_ffi_bridge_response_example}
final class BridgeResponseFrame {
  BridgeResponseFrame({
    required this.status,
    required List<MapEntry<String, String>> headers,
    required this.bodyBytes,
    this.detachedSocket,
  }) : _headers = headers,
       _headerNames = null,
       _headerValues = null;

  BridgeResponseFrame._decoded({
    required this.status,
    required List<String> headerNames,
    required List<String> headerValues,
    required this.bodyBytes,
    required this.detachedSocket,
  }) : _headers = null,
       _headerNames = headerNames,
       _headerValues = headerValues;

  /// Creates a response frame from already-flattened parallel header arrays.
  ///
  /// `headerNames` and `headerValues` must have equal lengths.
  factory BridgeResponseFrame.fromHeaderPairs({
    required int status,
    required List<String> headerNames,
    required List<String> headerValues,
    required Uint8List bodyBytes,
    BridgeDetachedSocket? detachedSocket,
  }) {
    if (headerNames.length != headerValues.length) {
      throw ArgumentError(
        'headerNames/headerValues length mismatch: '
        '${headerNames.length} != ${headerValues.length}',
      );
    }
    return BridgeResponseFrame._decoded(
      status: status,
      headerNames: headerNames,
      headerValues: headerValues,
      bodyBytes: bodyBytes,
      detachedSocket: detachedSocket,
    );
  }

  final int status;
  final Uint8List bodyBytes;
  final BridgeDetachedSocket? detachedSocket;
  List<MapEntry<String, String>>? _headers;
  final List<String>? _headerNames;
  final List<String>? _headerValues;

  List<MapEntry<String, String>> get headers =>
      _headers ??= _materializeHeaders();

  int get headerCount => _headerNames?.length ?? _headers?.length ?? 0;

  String headerNameAt(int index) {
    final names = _headerNames;
    if (names != null) {
      return names[index];
    }
    return _headers![index].key;
  }

  String headerValueAt(int index) {
    final values = _headerValues;
    if (values != null) {
      return values[index];
    }
    return _headers![index].value;
  }

  List<MapEntry<String, String>> _materializeHeaders() {
    final names = _headerNames;
    if (names == null || names.isEmpty) {
      return const <MapEntry<String, String>>[];
    }
    final values = _headerValues!;
    return List<MapEntry<String, String>>.generate(
      names.length,
      (i) => MapEntry(names[i], values[i]),
      growable: false,
    );
  }

  BridgeResponseFrame copyWith({
    int? status,
    List<MapEntry<String, String>>? headers,
    Uint8List? bodyBytes,
    BridgeDetachedSocket? detachedSocket,
  }) {
    return BridgeResponseFrame(
      status: status ?? this.status,
      headers: headers ?? this.headers,
      bodyBytes: bodyBytes ?? this.bodyBytes,
      detachedSocket: detachedSocket ?? this.detachedSocket,
    );
  }

  Uint8List encodePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseFrameType);
    writer.writeUint16(status);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      writer.writeString(headerNameAt(i));
      writer.writeString(headerValueAt(i));
    }
    writer.writeBytes(bodyBytes);
    return writer.takeBytes();
  }

  /// Encodes response metadata and body length, excluding body bytes.
  ///
  /// This is useful when body bytes are written separately to avoid one extra
  /// body copy when writing to a socket.
  Uint8List encodePayloadPrefixWithoutBody() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseFrameType);
    writer.writeUint16(status);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      writer.writeString(headerNameAt(i));
      writer.writeString(headerValueAt(i));
    }
    writer.writeUint32(bodyBytes.length);
    return writer.takeBytes();
  }

  factory BridgeResponseFrame.decodePayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final version = reader.readUint8();
    if (version != bridgeFrameProtocolVersion) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = reader.readUint8();
    if (frameType != _bridgeResponseFrameType) {
      throw FormatException('invalid bridge response frame type: $frameType');
    }
    final status = reader.readUint16();
    final headerCount = reader.readUint32();
    final headerNames = List<String>.filled(headerCount, '', growable: false);
    final headerValues = List<String>.filled(headerCount, '', growable: false);
    for (var i = 0; i < headerCount; i++) {
      headerNames[i] = reader.readString();
      headerValues[i] = reader.readString();
    }
    final bodyBytes = reader.readBytes();
    reader.ensureDone();
    return BridgeResponseFrame._decoded(
      status: status,
      headerNames: headerNames,
      headerValues: headerValues,
      bodyBytes: bodyBytes,
      detachedSocket: null,
    );
  }

  Uint8List encodeStartPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseStartFrameType);
    writer.writeUint16(status);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      writer.writeString(headerNameAt(i));
      writer.writeString(headerValueAt(i));
    }
    return writer.takeBytes();
  }

  factory BridgeResponseFrame.decodeStartPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final frameType = _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeResponseStartFrameType,
      frameLabel: 'response start',
    );
    if (frameType != _bridgeResponseStartFrameType) {
      throw StateError('unreachable');
    }
    final status = reader.readUint16();
    final headerCount = reader.readUint32();
    final headerNames = List<String>.filled(headerCount, '', growable: false);
    final headerValues = List<String>.filled(headerCount, '', growable: false);
    for (var i = 0; i < headerCount; i++) {
      headerNames[i] = reader.readString();
      headerValues[i] = reader.readString();
    }
    reader.ensureDone();
    return BridgeResponseFrame._decoded(
      status: status,
      headerNames: headerNames,
      headerValues: headerValues,
      bodyBytes: Uint8List(0),
      detachedSocket: null,
    );
  }

  static Uint8List encodeChunkPayload(List<int> chunkBytes) {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseChunkFrameType);
    writer.writeBytes(chunkBytes);
    return writer.takeBytes();
  }

  static Uint8List decodeChunkPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeResponseChunkFrameType,
      frameLabel: 'response chunk',
    );
    final chunk = reader.readBytes();
    reader.ensureDone();
    return chunk;
  }

  static Uint8List encodeEndPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseEndFrameType);
    return writer.takeBytes();
  }

  static void decodeEndPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeResponseEndFrameType,
      frameLabel: 'response end',
    );
    reader.ensureDone();
  }

  static bool isChunkPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeResponseChunkFrameType;
  }

  static bool isEndPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeResponseEndFrameType;
  }

  static int get chunkFrameType => _bridgeResponseChunkFrameType;
}

/// Binary frame helpers for upgraded socket tunnel payloads.
final class BridgeTunnelFrame {
  static int get chunkFrameType => _bridgeTunnelChunkFrameType;

  static int get closeFrameType => _bridgeTunnelCloseFrameType;

  static Uint8List encodeChunkPayload(List<int> chunkBytes) {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeTunnelChunkFrameType);
    writer.writeBytes(chunkBytes);
    return writer.takeBytes();
  }

  static Uint8List decodeChunkPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeTunnelChunkFrameType,
      frameLabel: 'tunnel chunk',
    );
    final chunk = reader.readBytes();
    reader.ensureDone();
    return chunk;
  }

  static Uint8List encodeClosePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeTunnelCloseFrameType);
    return writer.takeBytes();
  }

  static void decodeClosePayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeTunnelCloseFrameType,
      frameLabel: 'tunnel close',
    );
    reader.ensureDone();
  }

  static bool isChunkPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeTunnelChunkFrameType;
  }

  static bool isClosePayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeTunnelCloseFrameType;
  }
}

int _readAndValidateHeader(
  _BridgeFrameReader reader, {
  required int expectedFrameType,
  required String frameLabel,
}) {
  final version = reader.readUint8();
  if (version != bridgeFrameProtocolVersion) {
    throw FormatException('unsupported bridge protocol version: $version');
  }
  final frameType = reader.readUint8();
  if (frameType != expectedFrameType) {
    throw FormatException('invalid bridge $frameLabel frame type: $frameType');
  }
  return frameType;
}

int _peekFrameType(Uint8List payload) {
  if (payload.length < 2) {
    throw const FormatException('truncated bridge payload');
  }
  final version = payload[0];
  if (version != bridgeFrameProtocolVersion) {
    throw FormatException('unsupported bridge protocol version: $version');
  }
  return payload[1];
}

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

final class _BridgeFrameWriter {
  _BridgeFrameWriter([int initialCapacity = 256])
    : _buffer = Uint8List(initialCapacity) {
    _byteData = ByteData.view(_buffer.buffer);
  }

  Uint8List _buffer;
  late ByteData _byteData;
  int _length = 0;

  void writeUint8(int value) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, 'value');
    }
    _ensureCapacity(1);
    _buffer[_length] = value;
    _length += 1;
  }

  void writeUint16(int value) {
    if (value < 0 || value > 0xffff) {
      throw RangeError.range(value, 0, 0xffff, 'value');
    }
    _ensureCapacity(2);
    _byteData.setUint16(_length, value, Endian.big);
    _length += 2;
  }

  void writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, 'value');
    }
    _ensureCapacity(4);
    _byteData.setUint32(_length, value, Endian.big);
    _length += 4;
  }

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

  void writeBytes(List<int> bytes) {
    writeUint32(bytes.length);
    if (bytes.isNotEmpty) {
      _ensureCapacity(bytes.length);
      _buffer.setRange(_length, _length + bytes.length, bytes);
      _length += bytes.length;
    }
  }

  Uint8List takeBytes() => Uint8List.sublistView(_buffer, 0, _length);

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

final class _BridgeFrameReader {
  _BridgeFrameReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int readUint8() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  int readUint16() {
    _ensureAvailable(2);
    final value = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return value;
  }

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

  Uint8List readBytes() {
    final length = readUint32();
    _ensureAvailable(length);
    final start = _offset;
    _offset += length;
    return Uint8List.sublistView(_bytes, start, start + length);
  }

  void ensureDone() {
    if (_offset != _bytes.length) {
      throw FormatException(
        'unexpected trailing bridge payload bytes: ${_bytes.length - _offset}',
      );
    }
  }

  void _ensureAvailable(int count) {
    if (_offset + count > _bytes.length) {
      throw const FormatException('truncated bridge payload');
    }
  }
}
