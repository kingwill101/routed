import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed/routed.dart';
import 'package:routed_ffi/src/bridge/bridge_runtime.dart';
import 'package:routed_ffi/src/native/routed_ffi_native.dart';

const int _maxBridgeFrameBytes = 64 * 1024 * 1024;
const int _maxBridgeBodyBytes = 32 * 1024 * 1024;

final class _BridgeBinding {
  _BridgeBinding({
    required this.server,
    required this.backendKind,
    required this.backendHost,
    required this.backendPort,
    required this.backendPath,
    required this.dispose,
  });

  final ServerSocket server;
  final int backendKind;
  final String backendHost;
  final int backendPort;
  final String? backendPath;
  final Future<void> Function() dispose;
}

/// Request delivered to a direct FFI handler without Routed engine wrapping.
final class FfiDirectRequest {
  FfiDirectRequest({
    required this.method,
    required this.scheme,
    required this.authority,
    required this.path,
    required this.query,
    required this.protocol,
    required this.headers,
    required this.body,
  });

  final String method;
  final String scheme;
  final String authority;
  final String path;
  final String query;
  final String protocol;
  final List<MapEntry<String, String>> headers;
  final Stream<Uint8List> body;

  Uri get uri {
    final queryPart = query.isEmpty ? '' : '?$query';
    return Uri.parse('$scheme://$authority$path$queryPart');
  }

  String? header(String name) {
    for (final entry in headers) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }
}

/// Response returned by [FfiDirectHandler].
final class FfiDirectResponse {
  FfiDirectResponse.bytes({
    this.status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    Uint8List? bodyBytes,
  }) : headers = List<MapEntry<String, String>>.of(headers),
       bodyBytes = bodyBytes ?? Uint8List(0),
       body = null;

  FfiDirectResponse.stream({
    this.status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    required this.body,
  }) : headers = List<MapEntry<String, String>>.of(headers),
       bodyBytes = null;

  final int status;
  final List<MapEntry<String, String>> headers;
  final Uint8List? bodyBytes;
  final Stream<Uint8List>? body;
}

typedef FfiDirectHandler =
    FutureOr<FfiDirectResponse> Function(FfiDirectRequest request);

typedef _BridgeHandleFrame =
    Future<BridgeResponseFrame> Function(BridgeRequestFrame frame);

typedef _BridgeHandleStream =
    Future<void> Function({
      required BridgeRequestFrame frame,
      required Stream<Uint8List> bodyStream,
      required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
      required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
    });

/// Boots a Routed [engine] using a Rust-native transport front server.
///
/// The Rust transport terminates inbound HTTP traffic and forwards typed frames
/// to a private Dart bridge socket that invokes [Engine.handleRequest].
Future<void> serveFfi(
  Engine engine, {
  String host = '127.0.0.1',
  int? port,
  bool echo = true,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  final runtime = BridgeRuntime(engine);
  return _serveWithNativeProxy(
    host: host,
    port: port ?? 0,
    secure: false,
    echo: echo,
    http3: http3,
    shutdownSignal: shutdownSignal,
    onEcho: echo ? engine.printRoutes : null,
    handleFrame: runtime.handleFrame,
    handleStream: runtime.handleStream,
  );
}

/// Boots a Routed [engine] using the Rust-native transport entrypoint and TLS.
///
/// This requires PEM certificate and key files.
Future<void> serveSecureFfi(
  Engine engine, {
  String address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  bool? v6Only,
  bool? requestClientCertificate,
  bool? shared,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureFfi',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureFfi',
    );
  }

  if (certificatePassword != null && certificatePassword.isNotEmpty) {
    stderr.writeln(
      '[routed_ffi] certificatePassword is currently ignored in native TLS mode.',
    );
  }
  if (requestClientCertificate == true) {
    stderr.writeln(
      '[routed_ffi] requestClientCertificate is not yet implemented in native TLS mode.',
    );
  }
  if (v6Only != null || shared != null) {
    stderr.writeln(
      '[routed_ffi] v6Only/shared socket options are not yet configurable in native mode.',
    );
  }

  final runtime = BridgeRuntime(engine);
  return _serveWithNativeProxy(
    host: address,
    port: port,
    secure: true,
    echo: false,
    http3: http3,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    handleFrame: runtime.handleFrame,
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native transport and dispatches requests directly to [handler]
/// without Routed engine request/response wrapping.
Future<void> serveFfiDirect(
  FfiDirectHandler handler, {
  String host = '127.0.0.1',
  int? port,
  bool echo = true,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  return _serveWithNativeProxy(
    host: host,
    port: port ?? 0,
    secure: false,
    echo: echo,
    http3: http3,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) => _handleDirectFrame(handler, frame),
    handleStream:
        ({
          required frame,
          required bodyStream,
          required onResponseStart,
          required onResponseChunk,
        }) => _handleDirectStream(
          handler,
          frame: frame,
          bodyStream: bodyStream,
          onResponseStart: onResponseStart,
          onResponseChunk: onResponseChunk,
        ),
  );
}

/// Boots the Rust-native TLS transport and dispatches requests directly to
/// [handler] without Routed engine request/response wrapping.
Future<void> serveSecureFfiDirect(
  FfiDirectHandler handler, {
  String address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  bool? v6Only,
  bool? requestClientCertificate,
  bool? shared,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureFfiDirect',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureFfiDirect',
    );
  }

  if (certificatePassword != null && certificatePassword.isNotEmpty) {
    stderr.writeln(
      '[routed_ffi] certificatePassword is currently ignored in native TLS mode.',
    );
  }
  if (requestClientCertificate == true) {
    stderr.writeln(
      '[routed_ffi] requestClientCertificate is not yet implemented in native TLS mode.',
    );
  }
  if (v6Only != null || shared != null) {
    stderr.writeln(
      '[routed_ffi] v6Only/shared socket options are not yet configurable in native mode.',
    );
  }

  return _serveWithNativeProxy(
    host: address,
    port: port,
    secure: true,
    echo: false,
    http3: http3,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    handleFrame: (frame) => _handleDirectFrame(handler, frame),
    handleStream:
        ({
          required frame,
          required bodyStream,
          required onResponseStart,
          required onResponseChunk,
        }) => _handleDirectStream(
          handler,
          frame: frame,
          bodyStream: bodyStream,
          onResponseStart: onResponseStart,
          onResponseChunk: onResponseChunk,
        ),
  );
}

Future<void> _serveWithNativeProxy({
  required String host,
  required int port,
  required bool secure,
  required bool echo,
  required bool http3,
  required _BridgeHandleFrame handleFrame,
  required _BridgeHandleStream handleStream,
  void Function()? onEcho,
  Future<void>? shutdownSignal,
  String? tlsCertPath,
  String? tlsKeyPath,
}) async {
  // Ensure native symbol resolution and ABI compatibility are available.
  final abiVersion = transportAbiVersion();
  if (abiVersion <= 0) {
    throw StateError('Invalid routed_ffi native ABI version: $abiVersion');
  }

  onEcho?.call();

  final enableHttp3 = secure && http3;
  if (http3 && !secure) {
    stderr.writeln(
      '[routed_ffi] http3=true requested for insecure server; HTTP/3 requires TLS and will be disabled.',
    );
  }

  final bridgeBinding = await _bindBridgeServer();
  final bridgeServer = bridgeBinding.server;

  final bridgeSubscription = bridgeServer.listen((socket) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    // ignore: discarded_futures
    _handleBridgeSocket(
      socket,
      handleFrame: handleFrame,
      handleStream: handleStream,
    );
  });

  late final NativeProxyServer proxy;
  try {
    proxy = NativeProxyServer.start(
      host: host,
      port: port,
      backendHost: bridgeBinding.backendHost,
      backendPort: bridgeBinding.backendPort,
      backendKind: bridgeBinding.backendKind,
      backendPath: bridgeBinding.backendPath,
      enableHttp3: enableHttp3,
      tlsCertPath: tlsCertPath,
      tlsKeyPath: tlsKeyPath,
    );
  } catch (error) {
    await bridgeSubscription.cancel();
    await bridgeBinding.dispose();
    rethrow;
  }

  if (echo) {
    final scheme = secure ? 'https' : 'http';
    stdout.writeln(
      'Engine listening on $scheme://$host:${proxy.port} via routed_ffi '
      '(abi=$abiVersion, http3=$enableHttp3)',
    );
  }

  final done = Completer<void>();

  Future<void> stopAll() async {
    if (done.isCompleted) return;
    try {
      proxy.close();
    } catch (error, stack) {
      stderr.writeln('[routed_ffi] proxy shutdown error: $error\n$stack');
    }
    try {
      await bridgeSubscription.cancel();
    } catch (_) {}
    try {
      await bridgeBinding.dispose();
    } catch (_) {}
    done.complete();
  }

  // Fallback signal handling for transports that do not use Engine.serve().
  // ignore: discarded_futures
  ProcessSignal.sigint.watch().listen((_) => stopAll());
  // ignore: discarded_futures
  ProcessSignal.sigterm.watch().listen((_) => stopAll());
  if (shutdownSignal != null) {
    // ignore: discarded_futures
    shutdownSignal.whenComplete(stopAll);
  }

  bridgeSubscription.onDone(() {
    // ignore: discarded_futures
    stopAll();
  });

  await done.future;
}

Future<_BridgeBinding> _bindBridgeServer() async {
  if (Platform.isLinux || Platform.isMacOS) {
    final path = _bridgeUnixSocketPath();
    final unixAddress = InternetAddress(path, type: InternetAddressType.unix);
    try {
      final server = await ServerSocket.bind(unixAddress, 0);
      return _BridgeBinding(
        server: server,
        backendKind: bridgeBackendKindUnix,
        backendHost: '',
        backendPort: 0,
        backendPath: path,
        dispose: () async {
          await server.close();
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        },
      );
    } catch (error) {
      stderr.writeln(
        '[routed_ffi] unix bridge bind failed ($path): $error; falling back to loopback tcp.',
      );
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  return _BridgeBinding(
    server: server,
    backendKind: bridgeBackendKindTcp,
    backendHost: InternetAddress.loopbackIPv4.address,
    backendPort: server.port,
    backendPath: null,
    dispose: () => server.close(),
  );
}

String _bridgeUnixSocketPath() {
  final tempDir = Directory.systemTemp.path;
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '$tempDir/routed_ffi_bridge_${pid}_$timestamp.sock';
}

Future<void> _handleBridgeSocket(
  Socket socket, {
  required _BridgeHandleFrame handleFrame,
  required _BridgeHandleStream handleStream,
}) async {
  final reader = _SocketFrameReader(socket);
  try {
    while (true) {
      final firstPayload = await reader.readFrame();
      if (firstPayload == null) {
        return;
      }

      try {
        if (BridgeRequestFrame.isStartPayload(firstPayload)) {
          final startFrame = BridgeRequestFrame.decodeStartPayload(
            firstPayload,
          );
          await _handleChunkedBridgeRequest(
            socket,
            reader,
            handleStream: handleStream,
            startFrame: startFrame,
          );
          continue;
        }
      } catch (error) {
        await _writeBridgeBadRequest(socket, error);
        continue;
      }

      BridgeRequestFrame frame;
      try {
        frame = BridgeRequestFrame.decodePayload(firstPayload);
      } catch (error) {
        await _writeBridgeBadRequest(socket, error);
        continue;
      }

      final response = await handleFrame(frame);
      await _writeBridgeResponse(socket, response);
    }
  } catch (error, stack) {
    stderr.writeln('[routed_ffi] bridge socket error: $error\n$stack');
  } finally {
    await reader.cancel();
    try {
      await socket.flush();
    } catch (_) {}
    try {
      await socket.close();
    } catch (_) {}
  }
}

Future<void> _handleChunkedBridgeRequest(
  Socket socket,
  _SocketFrameReader reader, {
  required _BridgeHandleStream handleStream,
  required BridgeRequestFrame startFrame,
}) async {
  final requestBody = StreamController<Uint8List>();
  var requestBodyBytes = 0;
  var responseStarted = false;
  final handlerFuture = handleStream(
    frame: startFrame,
    bodyStream: requestBody.stream,
    onResponseStart: (frame) async {
      responseStarted = true;
      await _writeBridgeFrame(socket, frame.encodeStartPayload());
    },
    onResponseChunk: (chunkBytes) async {
      if (chunkBytes.isEmpty) {
        return;
      }
      if (!responseStarted) {
        throw StateError(
          'bridge response chunk emitted before response start frame',
        );
      }
      await _writeBridgeChunkFrame(
        socket,
        BridgeResponseFrame.chunkFrameType,
        chunkBytes,
      );
      await socket.flush();
    },
  );

  while (true) {
    try {
      final payload = await reader.readFrame();
      if (payload == null) {
        throw const FormatException('bridge stream ended before request end');
      }
      if (BridgeRequestFrame.isChunkPayload(payload)) {
        final chunk = BridgeRequestFrame.decodeChunkPayload(payload);
        if (chunk.isNotEmpty) {
          requestBodyBytes += chunk.length;
          if (requestBodyBytes > _maxBridgeBodyBytes) {
            throw FormatException(
              'bridge request body too large: $requestBodyBytes',
            );
          }
          requestBody.add(chunk);
        }
        continue;
      }
      if (BridgeRequestFrame.isEndPayload(payload)) {
        BridgeRequestFrame.decodeEndPayload(payload);
        break;
      }
      throw const FormatException(
        'unexpected bridge frame while reading request',
      );
    } catch (error, stack) {
      if (!requestBody.isClosed) {
        requestBody.addError(error, stack);
        await requestBody.close();
      }
      try {
        await handlerFuture;
      } catch (_) {}
      if (!responseStarted) {
        await _writeBridgeBadRequest(socket, error);
        return;
      }
      rethrow;
    }
  }

  if (!requestBody.isClosed) {
    await requestBody.close();
  }

  try {
    await handlerFuture;
    if (!responseStarted) {
      throw StateError('bridge response start frame was not emitted');
    }
    await _writeBridgeFrame(socket, BridgeResponseFrame.encodeEndPayload());
    await socket.flush();
  } catch (error) {
    if (!responseStarted) {
      await _writeBridgeBadRequest(socket, error);
      return;
    }
    rethrow;
  }
}

Future<BridgeResponseFrame> _handleDirectFrame(
  FfiDirectHandler handler,
  BridgeRequestFrame frame,
) async {
  try {
    final request = _toDirectRequest(
      frame,
      frame.bodyBytes.isEmpty
          ? const Stream<Uint8List>.empty()
          : Stream<Uint8List>.value(frame.bodyBytes),
    );
    final response = await handler(request);
    if (response.bodyBytes != null) {
      return BridgeResponseFrame(
        status: response.status,
        headers: response.headers,
        bodyBytes: response.bodyBytes!,
      );
    }
    final bodyBytes = await _collectDirectBodyBytes(response.body);
    return BridgeResponseFrame(
      status: response.status,
      headers: response.headers,
      bodyBytes: bodyBytes,
    );
  } catch (error, stack) {
    stderr.writeln('[routed_ffi] direct handler error: $error\n$stack');
    return _internalServerErrorFrame(error);
  }
}

Future<void> _handleDirectStream(
  FfiDirectHandler handler, {
  required BridgeRequestFrame frame,
  required Stream<Uint8List> bodyStream,
  required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
  required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
}) async {
  var responseStarted = false;
  try {
    final request = _toDirectRequest(frame, bodyStream);
    final response = await handler(request);
    await onResponseStart(
      BridgeResponseFrame(
        status: response.status,
        headers: response.headers,
        bodyBytes: Uint8List(0),
      ),
    );
    responseStarted = true;

    if (response.bodyBytes != null) {
      if (response.bodyBytes!.isNotEmpty) {
        await onResponseChunk(response.bodyBytes!);
      }
      return;
    }

    var totalBytes = 0;
    await for (final chunk
        in response.body ?? const Stream<Uint8List>.empty()) {
      if (chunk.isEmpty) {
        continue;
      }
      totalBytes += chunk.length;
      if (totalBytes > _maxBridgeBodyBytes) {
        throw FormatException('direct response body too large: $totalBytes');
      }
      await onResponseChunk(chunk);
    }
  } catch (error, stack) {
    if (responseStarted) {
      rethrow;
    }
    stderr.writeln('[routed_ffi] direct stream handler error: $error\n$stack');
    final errorResponse = _internalServerErrorFrame(error);
    await onResponseStart(
      BridgeResponseFrame(
        status: errorResponse.status,
        headers: errorResponse.headers,
        bodyBytes: Uint8List(0),
      ),
    );
    if (errorResponse.bodyBytes.isNotEmpty) {
      await onResponseChunk(errorResponse.bodyBytes);
    }
  }
}

FfiDirectRequest _toDirectRequest(
  BridgeRequestFrame frame,
  Stream<Uint8List> bodyStream,
) {
  return FfiDirectRequest(
    method: frame.method,
    scheme: frame.scheme,
    authority: frame.authority,
    path: frame.path,
    query: frame.query,
    protocol: frame.protocol,
    headers: frame.headers,
    body: bodyStream,
  );
}

Future<Uint8List> _collectDirectBodyBytes(Stream<Uint8List>? bodyStream) async {
  if (bodyStream == null) {
    return Uint8List(0);
  }
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in bodyStream) {
    if (chunk.isEmpty) {
      continue;
    }
    total += chunk.length;
    if (total > _maxBridgeBodyBytes) {
      throw FormatException('direct response body too large: $total');
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

BridgeResponseFrame _internalServerErrorFrame(Object error) {
  return BridgeResponseFrame(
    status: HttpStatus.internalServerError,
    headers: const <MapEntry<String, String>>[
      MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
    ],
    bodyBytes: Uint8List.fromList(utf8.encode('direct handler error: $error')),
  );
}

Future<void> _writeBridgeBadRequest(Socket socket, Object error) async {
  final errorResponse = BridgeResponseFrame(
    status: HttpStatus.badRequest,
    headers: const <MapEntry<String, String>>[],
    bodyBytes: Uint8List.fromList(
      utf8.encode('invalid bridge request: $error'),
    ),
  );
  await _writeBridgeResponse(socket, errorResponse);
}

Future<void> _writeBridgeResponse(
  Socket socket,
  BridgeResponseFrame response,
) async {
  await _writeBridgeFrame(socket, response.encodePayload());
  await socket.flush();
}

Future<void> _writeBridgeFrame(Socket socket, Uint8List payload) async {
  if (payload.length > _maxBridgeFrameBytes) {
    throw FormatException('bridge response frame too large: ${payload.length}');
  }
  final header = Uint8List(4);
  _writeUint32(header, 0, payload.length);
  socket.add(header);
  if (payload.isNotEmpty) {
    socket.add(payload);
  }
}

Future<void> _writeBridgeChunkFrame(
  Socket socket,
  int frameType,
  Uint8List chunkBytes,
) async {
  final payloadLength = 6 + chunkBytes.length;
  if (payloadLength > _maxBridgeFrameBytes) {
    throw FormatException('bridge response frame too large: $payloadLength');
  }
  final header = Uint8List(4);
  _writeUint32(header, 0, payloadLength);
  socket.add(header);

  final prefix = Uint8List(6);
  prefix[0] = bridgeFrameProtocolVersion;
  prefix[1] = frameType & 0xff;
  _writeUint32(prefix, 2, chunkBytes.length);
  socket.add(prefix);
  if (chunkBytes.isNotEmpty) {
    socket.add(chunkBytes);
  }
}

void _writeUint32(Uint8List target, int offset, int value) {
  target[offset] = (value >> 24) & 0xff;
  target[offset + 1] = (value >> 16) & 0xff;
  target[offset + 2] = (value >> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

int _readUint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

final class _SocketFrameReader {
  _SocketFrameReader(Socket socket)
    : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  final ListQueue<Uint8List> _chunks = ListQueue<Uint8List>();
  int _chunkOffset = 0;
  int _availableBytes = 0;

  Future<Uint8List?> readFrame() async {
    final header = await _readExactOrNull(4);
    if (header == null) {
      return null;
    }
    final payloadLength = _readUint32(header, 0);
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge frame too large: $payloadLength');
    }
    final payload = await _readExactOrNull(payloadLength);
    if (payload == null) {
      throw const FormatException('bridge stream ended before payload');
    }
    return payload;
  }

  Future<void> cancel() => _iterator.cancel();

  Future<Uint8List?> _readExactOrNull(int count) async {
    if (count == 0) {
      return Uint8List(0);
    }
    while (_availableBytes < count) {
      final hasNext = await _iterator.moveNext();
      if (!hasNext) {
        if (_availableBytes == 0) {
          return null;
        }
        throw const FormatException('bridge stream ended mid-frame');
      }
      final chunk = _iterator.current;
      if (chunk.isEmpty) {
        continue;
      }
      _chunks.addLast(chunk);
      _availableBytes += chunk.length;
    }

    // Fast path: satisfy the read directly from the current chunk view.
    if (_chunks.isNotEmpty) {
      final first = _chunks.first;
      final start = _chunkOffset;
      final remainingInFirst = first.length - start;
      if (remainingInFirst >= count) {
        final end = start + count;
        _chunkOffset = end;
        _availableBytes -= count;
        if (_chunkOffset == first.length) {
          _chunks.removeFirst();
          _chunkOffset = 0;
        }
        return Uint8List.sublistView(first, start, end);
      }
    }

    final out = Uint8List(count);
    var written = 0;
    while (written < count) {
      final chunk = _chunks.first;
      final start = _chunkOffset;
      final remainingInChunk = chunk.length - start;
      final needed = count - written;
      final take = remainingInChunk < needed ? remainingInChunk : needed;
      out.setRange(written, written + take, chunk, start);
      written += take;
      _chunkOffset += take;
      _availableBytes -= take;
      if (_chunkOffset == chunk.length) {
        _chunks.removeFirst();
        _chunkOffset = 0;
      }
    }
    return out;
  }
}
