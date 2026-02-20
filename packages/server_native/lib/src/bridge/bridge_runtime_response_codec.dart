part of 'bridge_runtime.dart';

/// A binary bridge response frame passed from Dart handlers back to Rust.
///
/// {@macro server_native_bridge_protocol_overview}
///
/// {@macro server_native_bridge_response_example}
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

  /// Materialized response headers in decode order.
  List<MapEntry<String, String>> get headers =>
      _headers ??= _materializeHeaders();

  /// Number of response headers.
  int get headerCount => _headerNames?.length ?? _headers?.length ?? 0;

  /// Returns header name at [index].
  String headerNameAt(int index) {
    final names = _headerNames;
    if (names != null) {
      return names[index];
    }
    return _headers![index].key;
  }

  /// Returns header value at [index].
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

  /// Returns a modified copy of this response frame.
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

  /// Encodes this response as a single payload frame.
  Uint8List encodePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_responseFrameTypeForEncode);
    writer.writeUint16(status);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      _writeHeaderName(
        writer,
        headerNameAt(i),
        tokenized: _encodeTokenizedHeaderFrameTypes,
      );
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
    writer.writeUint8(_responseFrameTypeForEncode);
    writer.writeUint16(status);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      _writeHeaderName(
        writer,
        headerNameAt(i),
        tokenized: _encodeTokenizedHeaderFrameTypes,
      );
      writer.writeString(headerValueAt(i));
    }
    writer.writeUint32(bodyBytes.length);
    return writer.takeBytes();
  }

  /// Decodes a single response payload frame.
  factory BridgeResponseFrame.decodePayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final version = reader.readUint8();
    if (!_isSupportedBridgeProtocolVersion(version)) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = reader.readUint8();
    if (!_isResponseFrameType(frameType)) {
      throw FormatException('invalid bridge response frame type: $frameType');
    }
    final tokenizedNames = _isTokenizedResponseFrameType(frameType);
    final status = reader.readUint16();
    final headerCount = reader.readUint32();
    final headerNames = List<String>.filled(headerCount, '', growable: false);
    final headerValues = List<String>.filled(headerCount, '', growable: false);
    for (var i = 0; i < headerCount; i++) {
      headerNames[i] = _readHeaderName(reader, tokenized: tokenizedNames);
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

  /// Encodes a response-start payload (streaming response mode).
  Uint8List encodeStartPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_responseStartFrameTypeForEncode);
    writer.writeUint16(status);
    writer.writeUint32(headerCount);
    for (var i = 0; i < headerCount; i++) {
      _writeHeaderName(
        writer,
        headerNameAt(i),
        tokenized: _encodeTokenizedHeaderFrameTypes,
      );
      writer.writeString(headerValueAt(i));
    }
    return writer.takeBytes();
  }

  /// Decodes a response-start payload.
  factory BridgeResponseFrame.decodeStartPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final version = reader.readUint8();
    if (!_isSupportedBridgeProtocolVersion(version)) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = reader.readUint8();
    if (!_isResponseStartFrameType(frameType)) {
      throw FormatException(
        'invalid bridge response start frame type: $frameType',
      );
    }
    final tokenizedNames = _isTokenizedResponseStartFrameType(frameType);
    final status = reader.readUint16();
    final headerCount = reader.readUint32();
    final headerNames = List<String>.filled(headerCount, '', growable: false);
    final headerValues = List<String>.filled(headerCount, '', growable: false);
    for (var i = 0; i < headerCount; i++) {
      headerNames[i] = _readHeaderName(reader, tokenized: tokenizedNames);
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

  /// Encodes one response chunk payload.
  static Uint8List encodeChunkPayload(List<int> chunkBytes) {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseChunkFrameType);
    writer.writeBytes(chunkBytes);
    return writer.takeBytes();
  }

  /// Decodes one response chunk payload.
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

  /// Encodes a response-end payload.
  static Uint8List encodeEndPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseEndFrameType);
    return writer.takeBytes();
  }

  /// Decodes and validates a response-end payload.
  static void decodeEndPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeResponseEndFrameType,
      frameLabel: 'response end',
    );
    reader.ensureDone();
  }

  /// Returns whether [payload] is a response chunk frame.
  static bool isChunkPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeResponseChunkFrameType;
  }

  /// Returns whether [payload] is a response-end frame.
  static bool isEndPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeResponseEndFrameType;
  }

  /// Response chunk frame type id.
  static int get chunkFrameType => _bridgeResponseChunkFrameType;
}

/// Binary frame helpers for upgraded socket tunnel payloads.
final class BridgeTunnelFrame {
  /// Tunnel chunk frame type id.
  static int get chunkFrameType => _bridgeTunnelChunkFrameType;

  /// Tunnel close frame type id.
  static int get closeFrameType => _bridgeTunnelCloseFrameType;

  /// Encodes one tunnel chunk payload.
  static Uint8List encodeChunkPayload(List<int> chunkBytes) {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeTunnelChunkFrameType);
    writer.writeBytes(chunkBytes);
    return writer.takeBytes();
  }

  /// Decodes one tunnel chunk payload.
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

  /// Encodes a tunnel-close payload.
  static Uint8List encodeClosePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeTunnelCloseFrameType);
    return writer.takeBytes();
  }

  /// Decodes and validates a tunnel-close payload.
  static void decodeClosePayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeTunnelCloseFrameType,
      frameLabel: 'tunnel close',
    );
    reader.ensureDone();
  }

  /// Returns whether [payload] is a tunnel-chunk frame.
  static bool isChunkPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeTunnelChunkFrameType;
  }

  /// Returns whether [payload] is a tunnel-close frame.
  static bool isClosePayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeTunnelCloseFrameType;
  }
}
