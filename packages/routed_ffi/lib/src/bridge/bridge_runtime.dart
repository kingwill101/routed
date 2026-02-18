// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed/routed.dart';
import 'package:routed/src/engine/http2_server.dart' show Http2Headers;

const int bridgeFrameProtocolVersion = 1;
const int _bridgeRequestFrameType = 1; // legacy single-frame request
const int _bridgeResponseFrameType = 2; // legacy single-frame response
const int _bridgeRequestStartFrameType = 3;
const int _bridgeRequestChunkFrameType = 4;
const int _bridgeRequestEndFrameType = 5;
const int _bridgeResponseStartFrameType = 6;
const int _bridgeResponseChunkFrameType = 7;
const int _bridgeResponseEndFrameType = 8;

final class BridgeRequestFrame {
  BridgeRequestFrame({
    required this.method,
    required this.scheme,
    required this.authority,
    required this.path,
    required this.query,
    required this.protocol,
    required this.headers,
    required this.bodyBytes,
  });

  final String method;
  final String scheme;
  final String authority;
  final String path;
  final String query;
  final String protocol;
  final List<MapEntry<String, String>> headers;
  final Uint8List bodyBytes;

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
    writer.writeUint32(headers.length);
    for (final entry in headers) {
      writer.writeString(entry.key);
      writer.writeString(entry.value);
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
    final headers = <MapEntry<String, String>>[];
    for (var i = 0; i < headerCount; i++) {
      headers.add(MapEntry(reader.readString(), reader.readString()));
    }
    final bodyBytes = reader.readBytes();
    reader.ensureDone();
    return BridgeRequestFrame(
      method: method.isEmpty ? 'GET' : method,
      scheme: scheme.isEmpty ? 'http' : scheme,
      authority: authority.isEmpty ? '127.0.0.1' : authority,
      path: path.isEmpty ? '/' : path,
      query: query,
      protocol: protocol.isEmpty ? '1.1' : protocol,
      headers: headers,
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
    writer.writeUint32(headers.length);
    for (final entry in headers) {
      writer.writeString(entry.key);
      writer.writeString(entry.value);
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
    final headers = <MapEntry<String, String>>[];
    for (var i = 0; i < headerCount; i++) {
      headers.add(MapEntry(reader.readString(), reader.readString()));
    }
    reader.ensureDone();
    return BridgeRequestFrame(
      method: method.isEmpty ? 'GET' : method,
      scheme: scheme.isEmpty ? 'http' : scheme,
      authority: authority.isEmpty ? '127.0.0.1' : authority,
      path: path.isEmpty ? '/' : path,
      query: query,
      protocol: protocol.isEmpty ? '1.1' : protocol,
      headers: headers,
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

final class BridgeResponseFrame {
  BridgeResponseFrame({
    required this.status,
    required this.headers,
    required this.bodyBytes,
  });

  final int status;
  final List<MapEntry<String, String>> headers;
  final Uint8List bodyBytes;

  BridgeResponseFrame copyWith({
    int? status,
    List<MapEntry<String, String>>? headers,
    Uint8List? bodyBytes,
  }) {
    return BridgeResponseFrame(
      status: status ?? this.status,
      headers: headers ?? this.headers,
      bodyBytes: bodyBytes ?? this.bodyBytes,
    );
  }

  Uint8List encodePayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseFrameType);
    writer.writeUint16(status);
    writer.writeUint32(headers.length);
    for (final entry in headers) {
      writer.writeString(entry.key);
      writer.writeString(entry.value);
    }
    writer.writeBytes(bodyBytes);
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
    final headers = <MapEntry<String, String>>[];
    for (var i = 0; i < headerCount; i++) {
      headers.add(MapEntry(reader.readString(), reader.readString()));
    }
    final bodyBytes = reader.readBytes();
    reader.ensureDone();
    return BridgeResponseFrame(
      status: status,
      headers: headers,
      bodyBytes: bodyBytes,
    );
  }

  Uint8List encodeStartPayload() {
    final writer = _BridgeFrameWriter();
    writer.writeUint8(bridgeFrameProtocolVersion);
    writer.writeUint8(_bridgeResponseStartFrameType);
    writer.writeUint16(status);
    writer.writeUint32(headers.length);
    for (final entry in headers) {
      writer.writeString(entry.key);
      writer.writeString(entry.value);
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
    final headers = <MapEntry<String, String>>[];
    for (var i = 0; i < headerCount; i++) {
      headers.add(MapEntry(reader.readString(), reader.readString()));
    }
    reader.ensureDone();
    return BridgeResponseFrame(
      status: status,
      headers: headers,
      bodyBytes: Uint8List(0),
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
    : _buffer = Uint8List(initialCapacity),
      _byteData = ByteData(initialCapacity);

  Uint8List _buffer;
  ByteData _byteData;
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

  void writeString(String value) => writeBytes(utf8.encode(value));

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

  String readString() => utf8.decode(readBytes(), allowMalformed: false);

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

final class BridgeRuntime {
  BridgeRuntime(this._engine);

  final Engine _engine;

  Future<void> handleStream({
    required BridgeRequestFrame frame,
    required Stream<Uint8List> bodyStream,
    required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
    required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
  }) async {
    final response = _BridgeStreamingHttpResponse(
      onStart: onResponseStart,
      onChunk: onResponseChunk,
    );
    final request = _BridgeHttpRequest(
      frame: frame,
      response: response,
      bodyStream: bodyStream,
    );
    await _engine.handleRequest(request);
    if (!response.isClosed) {
      await response.close();
    }
    await response.done;
  }

  Future<BridgeResponseFrame> handleFrame(BridgeRequestFrame frame) async {
    final response = _BridgeHttpResponse();
    final request = _BridgeHttpRequest(
      frame: frame,
      response: response,
      bodyStream: frame.bodyBytes.isEmpty
          ? const Stream<Uint8List>.empty()
          : Stream<Uint8List>.value(frame.bodyBytes),
    );
    await _engine.handleRequest(request);
    await response.done;

    final flattenedHeaders = <MapEntry<String, String>>[];
    response.headers.forEach((name, values) {
      for (final value in values) {
        flattenedHeaders.add(MapEntry(name, value));
      }
    });

    return BridgeResponseFrame(
      status: response.statusCode,
      headers: flattenedHeaders,
      bodyBytes: response.bodyBytes,
    );
  }
}

final class _BridgeHttpRequest extends Stream<Uint8List>
    implements HttpRequest {
  _BridgeHttpRequest({
    required BridgeRequestFrame frame,
    required this.response,
    required Stream<Uint8List> bodyStream,
  }) : method = frame.method,
       protocolVersion = frame.protocol,
       requestedUri = _buildUri(frame),
       _bodyStream = bodyStream,
       _headers = _buildHeaders(frame.headers) {
    final cookieValues = _headers[HttpHeaders.cookieHeader];
    if (cookieValues != null) {
      for (final header in cookieValues) {
        for (final part in header.split(';')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final idx = trimmed.indexOf('=');
          if (idx == -1) {
            cookies.add(Cookie(trimmed, ''));
          } else {
            cookies.add(
              Cookie(
                trimmed.substring(0, idx).trim(),
                trimmed.substring(idx + 1).trim(),
              ),
            );
          }
        }
      }
    }
  }

  static Uri _buildUri(BridgeRequestFrame frame) {
    final authority = _splitAuthority(frame.authority);
    return Uri(
      scheme: frame.scheme.isEmpty ? 'http' : frame.scheme,
      host: authority.host.isEmpty ? '127.0.0.1' : authority.host,
      port: authority.port,
      path: frame.path.isEmpty ? '/' : frame.path,
      query: frame.query.isEmpty ? null : frame.query,
    );
  }

  static Http2Headers _buildHeaders(List<MapEntry<String, String>> entries) {
    final headers = Http2Headers();
    for (final entry in entries) {
      headers.add(entry.key, entry.value);
    }
    return headers;
  }

  final Http2Headers _headers;
  final Stream<Uint8List> _bodyStream;

  @override
  final String method;

  @override
  final String protocolVersion;

  @override
  final Uri requestedUri;

  @override
  Uri get uri => requestedUri;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _headers.contentLength;

  @override
  final List<Cookie> cookies = <Cookie>[];

  @override
  bool persistentConnection = true;

  @override
  X509Certificate? get certificate => null;

  @override
  final HttpSession session = _BridgeSession();

  @override
  HttpConnectionInfo? get connectionInfo => const _BridgeConnectionInfo();

  @override
  final HttpResponse response;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _bodyStream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<Socket> detachSocket({bool writeHeaders = true}) {
    throw UnsupportedError('detachSocket is not supported by bridge requests');
  }

  Future<HttpClientResponse> upgrade(Future<void> Function(Socket p1) handler) {
    throw UnsupportedError('upgrade is not supported by bridge requests');
  }
}

final class _ParsedAuthority {
  const _ParsedAuthority({required this.host, required this.port});

  final String host;
  final int? port;
}

_ParsedAuthority _splitAuthority(String authority) {
  if (authority.isEmpty) {
    return const _ParsedAuthority(host: '127.0.0.1', port: null);
  }

  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end > 0) {
      final host = authority.substring(1, end);
      final suffix = authority.substring(end + 1);
      if (suffix.startsWith(':')) {
        final parsedPort = int.tryParse(suffix.substring(1));
        if (parsedPort != null) {
          return _ParsedAuthority(host: host, port: parsedPort);
        }
      }
      return _ParsedAuthority(host: host, port: null);
    }
  }

  final firstColon = authority.indexOf(':');
  final lastColon = authority.lastIndexOf(':');
  if (firstColon != -1 && firstColon == lastColon) {
    final host = authority.substring(0, firstColon);
    final parsedPort = int.tryParse(authority.substring(firstColon + 1));
    if (parsedPort != null) {
      return _ParsedAuthority(host: host, port: parsedPort);
    }
  }

  return _ParsedAuthority(host: authority, port: null);
}

final class _BridgeHttpResponse implements HttpResponse {
  _BridgeHttpResponse();

  final Http2Headers _headers = Http2Headers();
  final List<Cookie> _cookies = <Cookie>[];
  final BytesBuilder _body = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  bool _closed = false;
  Encoding _encoding = utf8;

  Uint8List get bodyBytes => _body.toBytes();

  @override
  int statusCode = HttpStatus.ok;

  @override
  String reasonPhrase = 'OK';

  @override
  bool persistentConnection = true;

  @override
  Duration? deadline;

  @override
  bool bufferOutput = true;

  @override
  HttpHeaders get headers => _headers;

  @override
  List<Cookie> get cookies => _cookies;

  @override
  int get contentLength => headers.contentLength;

  @override
  set contentLength(int value) => headers.contentLength = value;

  @override
  HttpConnectionInfo? get connectionInfo => const _BridgeConnectionInfo();

  @override
  void add(List<int> data) {
    _ensureOpen();
    _body.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    _ensureOpen();
    await for (final chunk in stream) {
      _body.add(chunk);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding value) => _encoding = value;

  @override
  void write(Object? object) => add(encoding.encode(object?.toString() ?? ''));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  Future<void> flush() async {}

  @override
  Future<void> redirect(
    Uri location, {
    int status = HttpStatus.movedTemporarily,
  }) async {
    headers.set(HttpHeaders.locationHeader, location.toString());
    statusCode = status;
    await close();
  }

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) {
    throw UnsupportedError('detachSocket is not supported by bridge response');
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Response is already closed');
    }
  }
}

final class _BridgeStreamingHttpResponse implements HttpResponse {
  _BridgeStreamingHttpResponse({required this.onStart, required this.onChunk});

  final Future<void> Function(BridgeResponseFrame frame) onStart;
  final Future<void> Function(Uint8List chunkBytes) onChunk;

  final Http2Headers _headers = Http2Headers();
  final List<Cookie> _cookies = <Cookie>[];
  final Completer<void> _done = Completer<void>();
  Future<void> _pendingWrite = Future<void>.value();
  bool _closed = false;
  bool _started = false;
  Encoding _encoding = utf8;

  bool get isClosed => _closed;

  @override
  int statusCode = HttpStatus.ok;

  @override
  String reasonPhrase = 'OK';

  @override
  bool persistentConnection = true;

  @override
  Duration? deadline;

  @override
  bool bufferOutput = true;

  @override
  HttpHeaders get headers => _headers;

  @override
  List<Cookie> get cookies => _cookies;

  @override
  int get contentLength => headers.contentLength;

  @override
  set contentLength(int value) => headers.contentLength = value;

  @override
  HttpConnectionInfo? get connectionInfo => const _BridgeConnectionInfo();

  @override
  void add(List<int> data) {
    _ensureOpen();
    if (data.isEmpty) {
      return;
    }
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    _enqueueWrite(() async {
      await _ensureStarted();
      await onChunk(chunk);
    });
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    _ensureOpen();
    await for (final chunk in stream) {
      add(chunk);
    }
    await _pendingWrite;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _enqueueWrite(_ensureStarted);
    await _pendingWrite;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding value) => _encoding = value;

  @override
  void write(Object? object) => add(encoding.encode(object?.toString() ?? ''));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  Future<void> flush() async => _pendingWrite;

  @override
  Future<void> redirect(
    Uri location, {
    int status = HttpStatus.movedTemporarily,
  }) async {
    headers.set(HttpHeaders.locationHeader, location.toString());
    statusCode = status;
    await close();
  }

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) {
    throw UnsupportedError('detachSocket is not supported by bridge response');
  }

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    _started = true;

    final flattenedHeaders = <MapEntry<String, String>>[];
    headers.forEach((name, values) {
      for (final value in values) {
        flattenedHeaders.add(MapEntry(name, value));
      }
    });
    for (final cookie in _cookies) {
      flattenedHeaders.add(
        MapEntry(HttpHeaders.setCookieHeader, cookie.toString()),
      );
    }

    await onStart(
      BridgeResponseFrame(
        status: statusCode,
        headers: flattenedHeaders,
        bodyBytes: Uint8List(0),
      ),
    );
  }

  void _enqueueWrite(Future<void> Function() action) {
    _pendingWrite = _pendingWrite.then((_) => action()).catchError((
      error,
      stack,
    ) {
      if (!_done.isCompleted) {
        _done.completeError(error, stack);
      }
    });
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Response is already closed');
    }
  }
}

final class _BridgeConnectionInfo implements HttpConnectionInfo {
  const _BridgeConnectionInfo();

  @override
  int get localPort => 0;

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 0;
}

final class _BridgeSession extends MapBase<dynamic, dynamic>
    implements HttpSession {
  @override
  String id = 'bridge';

  @override
  bool isNew = false;

  final Map<String, dynamic> _data = <String, dynamic>{};

  Duration timeout = const Duration(minutes: 20);

  @override
  void destroy() => _data.clear();

  @override
  set onTimeout(void Function() callback) {}

  @override
  dynamic operator [](Object? key) => key is String ? _data[key] : null;

  @override
  void clear() => _data.clear();

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  void operator []=(Object? key, dynamic value) {
    if (key is! String) {
      throw ArgumentError('Session keys must be strings');
    }
    _data[key] = value;
  }

  @override
  dynamic remove(Object? key) => key is String ? _data.remove(key) : null;
}
