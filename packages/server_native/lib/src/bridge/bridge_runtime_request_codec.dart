part of 'bridge_runtime.dart';

/// A binary bridge request frame passed from Rust transport to Dart.
///
/// {@macro server_native_bridge_protocol_overview}
///
/// {@macro server_native_bridge_request_example}
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

  /// Materialized request headers in decode order.
  List<MapEntry<String, String>> get headers =>
      _headers ??= _materializeHeaders();

  /// Number of request headers.
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

  /// Iterates all request headers without forcing extra allocations.
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

  /// Returns a modified copy of this request frame.
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

  /// Encodes this request as a single payload frame.
  Uint8List encodePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_requestFrameTypeForEncode);
    writer.writeString(method);
    writer.writeString(scheme);
    writer.writeString(authority);
    writer.writeString(path);
    writer.writeString(query);
    writer.writeString(protocol);
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

  /// Decodes a single request payload frame.
  factory BridgeRequestFrame.decodePayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final version = reader.readUint8();
    if (!_isSupportedBridgeProtocolVersion(version)) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = reader.readUint8();
    if (!_isRequestFrameType(frameType)) {
      throw FormatException('invalid bridge request frame type: $frameType');
    }
    final tokenizedNames = _isTokenizedRequestFrameType(frameType);

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
      headerNames[i] = _readHeaderName(reader, tokenized: tokenizedNames);
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

  /// Encodes the request-start payload used for streamed request bodies.
  Uint8List encodeStartPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_requestStartFrameTypeForEncode);
    writer.writeString(method);
    writer.writeString(scheme);
    writer.writeString(authority);
    writer.writeString(path);
    writer.writeString(query);
    writer.writeString(protocol);
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

  /// Decodes a request-start payload.
  factory BridgeRequestFrame.decodeStartPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    final version = reader.readUint8();
    if (!_isSupportedBridgeProtocolVersion(version)) {
      throw FormatException('unsupported bridge protocol version: $version');
    }
    final frameType = reader.readUint8();
    if (!_isRequestStartFrameType(frameType)) {
      throw FormatException(
        'invalid bridge request start frame type: $frameType',
      );
    }
    final tokenizedNames = _isTokenizedRequestStartFrameType(frameType);
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
      headerNames[i] = _readHeaderName(reader, tokenized: tokenizedNames);
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

  /// Encodes one request chunk payload.
  static Uint8List encodeChunkPayload(List<int> chunkBytes) {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeRequestChunkFrameType);
    writer.writeBytes(chunkBytes);
    return writer.takeBytes();
  }

  /// Decodes one request chunk payload.
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

  /// Encodes the request-end payload.
  static Uint8List encodeEndPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeRequestEndFrameType);
    return writer.takeBytes();
  }

  /// Decodes and validates a request-end payload.
  static void decodeEndPayload(Uint8List payload) {
    final reader = _BridgeFrameReader(payload);
    _readAndValidateHeader(
      reader,
      expectedFrameType: _bridgeRequestEndFrameType,
      frameLabel: 'request end',
    );
    reader.ensureDone();
  }

  /// Returns whether [payload] is a request-chunk frame.
  static bool isChunkPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeRequestChunkFrameType;
  }

  /// Returns whether [payload] is a request-end frame.
  static bool isEndPayload(Uint8List payload) {
    return _peekFrameType(payload) == _bridgeRequestEndFrameType;
  }

  /// Request chunk frame type id.
  static int get chunkFrameType => _bridgeRequestChunkFrameType;

  /// Request end frame type id.
  static int get endFrameType => _bridgeRequestEndFrameType;

  /// Returns whether [payload] is a request-start frame.
  static bool isStartPayload(Uint8List payload) {
    return _isRequestStartFrameType(_peekFrameType(payload));
  }
}
