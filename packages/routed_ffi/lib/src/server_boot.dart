import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed/routed.dart';
import 'package:routed_ffi/src/bridge/bridge_runtime.dart';
import 'package:routed_ffi/src/native/routed_ffi_native.dart';
import 'package:routed_ffi/src/routed/routed_bridge_runtime.dart';

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
    required String method,
    required String scheme,
    required String authority,
    required String path,
    required String query,
    required String protocol,
    required List<MapEntry<String, String>> headers,
    required this.body,
  }) : _frame = null,
       _method = method,
       _scheme = scheme,
       _authority = authority,
       _path = path,
       _query = query,
       _protocol = protocol,
       _headers = List<MapEntry<String, String>>.unmodifiable(headers);

  FfiDirectRequest._fromFrame(this._frame, this.body)
    : _method = null,
      _scheme = null,
      _authority = null,
      _path = null,
      _query = null,
      _protocol = null,
      _headers = null;

  final BridgeRequestFrame? _frame;
  final String? _method;
  final String? _scheme;
  final String? _authority;
  final String? _path;
  final String? _query;
  final String? _protocol;
  List<MapEntry<String, String>>? _headers;
  final Stream<Uint8List> body;

  String get method => _frame?.method ?? _method!;

  String get scheme => _frame?.scheme ?? _scheme!;

  String get authority => _frame?.authority ?? _authority!;

  String get path => _frame?.path ?? _path!;

  String get query => _frame?.query ?? _query!;

  String get protocol => _frame?.protocol ?? _protocol!;

  List<MapEntry<String, String>> get headers {
    final headers = _headers;
    if (headers != null) {
      return headers;
    }
    final frame = _frame;
    if (frame == null) {
      return const <MapEntry<String, String>>[];
    }
    final view = UnmodifiableListView(_DirectHeaderListView(frame));
    _headers = view;
    return view;
  }

  late final Uri uri = _buildDirectUri(
    scheme: scheme,
    authority: authority,
    path: path,
    query: query,
  );

  String? header(String name) {
    final frame = _frame;
    if (frame != null) {
      for (var i = 0; i < frame.headerCount; i++) {
        if (_equalsAsciiIgnoreCase(frame.headerNameAt(i), name)) {
          return frame.headerValueAt(i);
        }
      }
      return null;
    }

    final target = name;
    for (final entry in headers) {
      if (_equalsAsciiIgnoreCase(entry.key, target)) {
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
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  final runtime = RoutedBridgeRuntime(engine);
  final normalizedHost = _normalizeBindHost(host, 'host');
  return _serveWithNativeProxy(
    host: normalizedHost,
    port: port ?? 0,
    secure: false,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: false,
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
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
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

  final runtime = RoutedBridgeRuntime(engine);
  final normalizedAddress = _normalizeBindHost(address, 'address');
  return _serveWithNativeProxy(
    host: normalizedAddress,
    port: port,
    secure: true,
    echo: false,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http3: http3,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: runtime.handleFrame,
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
Future<void> serveFfiHttp(
  BridgeHttpHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  final runtime = BridgeHttpRuntime(handler);
  final normalizedHost = _normalizeBindHost(host, 'host');
  return _serveWithNativeProxy(
    host: normalizedHost,
    port: port ?? 0,
    secure: false,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: false,
    http3: http3,
    shutdownSignal: shutdownSignal,
    handleFrame: runtime.handleFrame,
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native TLS transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
Future<void> serveSecureFfiHttp(
  BridgeHttpHandler handler, {
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureFfiHttp',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureFfiHttp',
    );
  }

  final runtime = BridgeHttpRuntime(handler);
  final normalizedAddress = _normalizeBindHost(address, 'address');
  return _serveWithNativeProxy(
    host: normalizedAddress,
    port: port,
    secure: true,
    echo: false,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http3: http3,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: runtime.handleFrame,
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native transport and dispatches requests directly to [handler]
/// without Routed engine request/response wrapping.
Future<void> serveFfiDirect(
  FfiDirectHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http3 = true,
  Future<void>? shutdownSignal,
}) {
  final normalizedHost = _normalizeBindHost(host, 'host');
  return _serveWithNativeProxy(
    host: normalizedHost,
    port: port ?? 0,
    secure: false,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: false,
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
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
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

  final normalizedAddress = _normalizeBindHost(address, 'address');
  return _serveWithNativeProxy(
    host: normalizedAddress,
    port: port,
    secure: true,
    echo: false,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http3: http3,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
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
  required int backlog,
  required bool v6Only,
  required bool shared,
  required bool requestClientCertificate,
  required bool http3,
  required _BridgeHandleFrame handleFrame,
  required _BridgeHandleStream handleStream,
  void Function()? onEcho,
  Future<void>? shutdownSignal,
  String? tlsCertPath,
  String? tlsKeyPath,
  String? tlsCertPassword,
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
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      requestClientCertificate: requestClientCertificate,
      enableHttp3: enableHttp3,
      tlsCertPath: tlsCertPath,
      tlsKeyPath: tlsKeyPath,
      tlsCertPassword: tlsCertPassword,
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
  final writer = _BridgeSocketWriter(socket);
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
            reader,
            writer,
            handleStream: handleStream,
            startFrame: startFrame,
          );
          continue;
        }
      } catch (error) {
        _writeBridgeBadRequest(writer, error);
        continue;
      }

      BridgeRequestFrame frame;
      try {
        frame = BridgeRequestFrame.decodePayload(firstPayload);
      } catch (error) {
        _writeBridgeBadRequest(writer, error);
        continue;
      }

      final response = await handleFrame(frame);
      _writeBridgeResponse(writer, response);
      final detachedSocket = response.detachedSocket;
      if (detachedSocket != null) {
        await _runDetachedSocketTunnel(reader, writer, detachedSocket);
        return;
      }
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

String _normalizeBindHost(Object value, String name) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty');
    }
    return trimmed;
  }
  if (value is InternetAddress) {
    return value.address;
  }
  throw ArgumentError.value(
    value,
    name,
    '$name must be a String or InternetAddress',
  );
}

Future<void> _handleChunkedBridgeRequest(
  _SocketFrameReader reader,
  _BridgeSocketWriter writer, {
  required _BridgeHandleStream handleStream,
  required BridgeRequestFrame startFrame,
}) async {
  final requestBody = StreamController<Uint8List>(sync: true);
  var requestBodyBytes = 0;
  var responseStarted = false;
  BridgeDetachedSocket? detachedSocket;
  final handlerFuture = handleStream(
    frame: startFrame,
    bodyStream: requestBody.stream,
    onResponseStart: (frame) async {
      responseStarted = true;
      detachedSocket = frame.detachedSocket;
      writer.writeFrame(frame.encodeStartPayload());
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
      writer.writeChunkFrame(
        BridgeResponseFrame.chunkFrameType,
        chunkBytes,
      );
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
        _writeBridgeBadRequest(writer, error);
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
    writer.writeFrame(BridgeResponseFrame.encodeEndPayload());
    if (detachedSocket != null) {
      await _runDetachedSocketTunnel(reader, writer, detachedSocket!);
      return;
    }
  } catch (error) {
    if (!responseStarted) {
      _writeBridgeBadRequest(writer, error);
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
  return FfiDirectRequest._fromFrame(frame, bodyStream);
}

Uri _buildDirectUri({
  required String scheme,
  required String authority,
  required String path,
  required String query,
}) {
  final parsed = _splitDirectAuthority(authority);
  return Uri(
    scheme: scheme.isEmpty ? 'http' : scheme,
    host: parsed.host.isEmpty ? '127.0.0.1' : parsed.host,
    port: parsed.port,
    path: path.isEmpty ? '/' : path,
    query: query.isEmpty ? null : query,
  );
}

final class _DirectAuthority {
  const _DirectAuthority({required this.host, required this.port});

  final String host;
  final int? port;
}

_DirectAuthority _splitDirectAuthority(String authority) {
  if (authority.isEmpty) {
    return const _DirectAuthority(host: '127.0.0.1', port: null);
  }

  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end > 0) {
      final host = authority.substring(1, end);
      final suffix = authority.substring(end + 1);
      if (suffix.startsWith(':')) {
        final parsedPort = int.tryParse(suffix.substring(1));
        if (parsedPort != null) {
          return _DirectAuthority(host: host, port: parsedPort);
        }
      }
      return _DirectAuthority(host: host, port: null);
    }
  }

  final firstColon = authority.indexOf(':');
  final lastColon = authority.lastIndexOf(':');
  if (firstColon != -1 && firstColon == lastColon) {
    final host = authority.substring(0, firstColon);
    final parsedPort = int.tryParse(authority.substring(firstColon + 1));
    if (parsedPort != null) {
      return _DirectAuthority(host: host, port: parsedPort);
    }
  }

  return _DirectAuthority(host: authority, port: null);
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

void _writeBridgeBadRequest(_BridgeSocketWriter writer, Object error) {
  final errorResponse = BridgeResponseFrame(
    status: HttpStatus.badRequest,
    headers: const <MapEntry<String, String>>[],
    bodyBytes: Uint8List.fromList(
      utf8.encode('invalid bridge request: $error'),
    ),
  );
  _writeBridgeResponse(writer, errorResponse);
}

void _writeBridgeResponse(
  _BridgeSocketWriter writer,
  BridgeResponseFrame response,
) {
  writer.writeResponseFrame(response);
}

Future<void> _runDetachedSocketTunnel(
  _SocketFrameReader reader,
  _BridgeSocketWriter writer,
  BridgeDetachedSocket detachedSocket,
) async {
  final bridgeSocket = detachedSocket.bridgeSocket;

  final outboundTask = () async {
    try {
      await for (final chunk in bridgeSocket) {
        if (chunk.isEmpty) {
          continue;
        }
        await writer.writeChunkFrameAndFlush(
          BridgeTunnelFrame.chunkFrameType,
          chunk,
        );
      }
    } catch (_) {
      // Peer bridge disconnect and write errors both terminate the tunnel.
    }
  }();

  try {
    while (true) {
      final payload = await reader.readFrame();
      if (payload == null) {
        break;
      }
      if (BridgeTunnelFrame.isChunkPayload(payload)) {
        final chunk = BridgeTunnelFrame.decodeChunkPayload(payload);
        if (chunk.isNotEmpty) {
          bridgeSocket.add(chunk);
        }
        continue;
      }
      if (BridgeTunnelFrame.isClosePayload(payload)) {
        BridgeTunnelFrame.decodeClosePayload(payload);
        break;
      }
      throw const FormatException(
        'unexpected bridge frame while detached socket tunnel is active',
      );
    }
  } finally {
    await detachedSocket.close();
    try {
      await outboundTask;
    } catch (_) {}
  }
}

final class _BridgeSocketWriter {
  _BridgeSocketWriter(this._socket);

  final Socket _socket;

  void writeFrame(Uint8List payload) {
    if (payload.length > _maxBridgeFrameBytes) {
      throw FormatException(
        'bridge response frame too large: ${payload.length}',
      );
    }
    final header = Uint32List(1);
    ByteData.sublistView(header).setUint32(0, payload.length, Endian.big);
    _socket.add(header.buffer.asUint8List());
    if (payload.isNotEmpty) {
      _socket.add(payload);
    }
  }

  void writeResponseFrame(BridgeResponseFrame response) {
    final body = response.bodyBytes;
    final prefix = response.encodePayloadPrefixWithoutBody();
    final payloadLength = prefix.length + body.length;
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge response frame too large: $payloadLength');
    }
    final header = Uint32List(1);
    ByteData.sublistView(header).setUint32(0, payloadLength, Endian.big);
    _socket.add(header.buffer.asUint8List());
    _socket.add(prefix);
    if (body.isNotEmpty) {
      _socket.add(body);
    }
  }

  void writeChunkFrame(int frameType, Uint8List chunkBytes) {
    final payloadLength = 6 + chunkBytes.length;
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge response frame too large: $payloadLength');
    }
    final prelude = Uint8List(10);
    final preludeData = ByteData.sublistView(prelude);
    preludeData.setUint32(0, payloadLength, Endian.big);
    prelude[4] = bridgeFrameProtocolVersion;
    prelude[5] = frameType & 0xff;
    preludeData.setUint32(6, chunkBytes.length, Endian.big);
    _socket.add(prelude);
    if (chunkBytes.isNotEmpty) {
      _socket.add(chunkBytes);
    }
  }

  Future<void> writeChunkFrameAndFlush(
    int frameType,
    Uint8List chunkBytes,
  ) async {
    writeChunkFrame(frameType, chunkBytes);
    await _socket.flush();
  }
}

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

final class _SocketFrameReader {
  _SocketFrameReader(Socket socket)
    : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  final ListQueue<Uint8List> _chunks = ListQueue<Uint8List>();
  int _chunkOffset = 0;
  int _availableBytes = 0;

  Future<Uint8List?> readFrame() async {
    final headerBytes = await _readExactOrNull(4);
    if (headerBytes == null) {
      return null;
    }
    final payloadLength = ByteData.sublistView(
      headerBytes,
    ).getUint32(0, Endian.big);
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
    final hasBytes = await _ensureAvailableOrNull(count);
    if (!hasBytes) {
      return null;
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

  Future<bool> _ensureAvailableOrNull(int count) async {
    while (_availableBytes < count) {
      final hasNext = await _iterator.moveNext();
      if (!hasNext) {
        if (_availableBytes == 0) {
          return false;
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
    return true;
  }
}
