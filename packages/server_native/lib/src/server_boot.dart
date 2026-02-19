import 'dart:async';
import 'dart:ffi';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/src/bridge/bridge_runtime.dart';
import 'package:server_native/src/native/server_native_transport.dart';

part 'server_boot_api.dart';
part 'server_boot_http_server.dart';

const int _maxBridgeFrameBytes = 64 * 1024 * 1024;
const int _maxBridgeBodyBytes = 32 * 1024 * 1024;
const int _coalescePayloadThresholdBytes = 4 * 1024;
const int _bridgeRequestFrameTypeLegacy = 1;
const int _bridgeRequestFrameTypeTokenized = 11;
const int _bridgeHeaderNameLiteralToken = 0xffff;
const Utf8Decoder _directStrictUtf8Decoder = Utf8Decoder(allowMalformed: false);
const List<String> _directBridgeHeaderNameTable = <String>[
  'host',
  'connection',
  'user-agent',
  'accept',
  'accept-encoding',
  'accept-language',
  'content-type',
  'content-length',
  'transfer-encoding',
  'cookie',
  'set-cookie',
  'cache-control',
  'pragma',
  'upgrade',
  'authorization',
  'origin',
  'referer',
  'location',
  'server',
  'date',
  'x-forwarded-for',
  'x-forwarded-proto',
  'x-forwarded-host',
  'x-forwarded-port',
  'x-request-id',
  'sec-websocket-key',
  'sec-websocket-version',
  'sec-websocket-protocol',
  'sec-websocket-extensions',
];

/// {@template server_native_serve_handler_example}
/// Example:
/// ```dart
/// await serveNative(
///   (request) async {
///     request.response
///       ..statusCode = HttpStatus.ok
///       ..headers.contentType = ContentType.text
///       ..write('ok');
///     await request.response.close();
///   },
///   host: InternetAddress.loopbackIPv4,
///   port: 8080,
/// );
/// ```
/// {@endtemplate}
///
/// {@template server_native_serve_http_handler_example}
/// Example:
/// ```dart
/// await serveNativeHttp((request) async {
///   request.response
///     ..statusCode = HttpStatus.ok
///     ..headers.contentType = ContentType.text
///     ..write('ok');
///   await request.response.close();
/// }, host: InternetAddress.loopbackIPv4, port: 8080);
/// ```
/// {@endtemplate}

@pragma('vm:prefer-inline')
int? _directHeaderLookupToken(String name) {
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

Future<InternetAddress> _resolveInternetAddress(String host) async {
  final parsed = InternetAddress.tryParse(host);
  if (parsed != null) {
    return parsed;
  }
  final resolved = await InternetAddress.lookup(host);
  if (resolved.isEmpty) {
    throw StateError('Unable to resolve host "$host"');
  }
  return resolved.first;
}

final class _BridgeHandleFrameResult {
  _BridgeHandleFrameResult.frame(BridgeResponseFrame frame)
    : _frame = frame,
      _encodedPayload = null;

  _BridgeHandleFrameResult.encoded(Uint8List payload)
    : _frame = null,
      _encodedPayload = payload;

  final BridgeResponseFrame? _frame;
  final Uint8List? _encodedPayload;

  BridgeResponseFrame get frame => _frame!;

  Uint8List? get encodedPayload => _encodedPayload;

  BridgeDetachedSocket? get detachedSocket => _frame?.detachedSocket;
}

final class _NativeDirectRequestStreamState {
  _NativeDirectRequestStreamState(this.requestBody);

  final StreamController<Uint8List> requestBody;
  BridgeDetachedSocket? detachedSocket;
}

/// Boots the Rust-native transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// {@macro server_native_serve_handler_example}
Future<void> serveNative(
  BridgeHttpHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
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
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native TLS transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// This requires PEM certificate and key files.
///
/// {@macro server_native_serve_handler_example}
Future<void> serveSecureNative(
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
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNative',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNative',
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
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots one logical handler across multiple Rust-native listeners.
///
/// Similar to `http_multi_server`, this runs one handler behind several bind
/// addresses. The only per-listener difference is host/port binding.
///
/// {@macro server_native_multi_bind_example}
Future<void> serveNativeMulti(
  BridgeHttpHandler handler, {
  required List<NativeServerBind> binds,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) async {
  if (binds.isEmpty) {
    throw ArgumentError.value(binds, 'binds', 'binds must not be empty');
  }

  final runtime = BridgeHttpRuntime(handler);
  final internalShutdown = Completer<void>();
  if (shutdownSignal != null) {
    // ignore: discarded_futures
    shutdownSignal.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  final futures = <Future<void>>[];
  for (var i = 0; i < binds.length; i++) {
    final bind = binds[i];
    final normalizedHost = _normalizeBindHost(bind.host, 'binds[$i].host');
    final future = _serveWithNativeProxy(
      host: normalizedHost,
      port: bind.port,
      secure: false,
      echo: echo,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      requestClientCertificate: false,
      http2: http2,
      http3: http3,
      nativeDirectCallback: nativeCallback,
      shutdownSignal: internalShutdown.future,
      handleFrame: (frame) async =>
          _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
      handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
        await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
      ),
      handleStream: runtime.handleStream,
    );
    futures.add(future);
    // Any listener completion (error or normal) should stop all listeners.
    // ignore: discarded_futures
    future.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  await Future.wait(futures);
}

/// Boots one logical handler across multiple Rust-native TLS listeners.
///
/// {@macro server_native_multi_bind_example}
Future<void> serveSecureNativeMulti(
  BridgeHttpHandler handler, {
  required List<NativeServerBind> binds,
  required String certificatePath,
  required String keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) async {
  if (binds.isEmpty) {
    throw ArgumentError.value(binds, 'binds', 'binds must not be empty');
  }
  if (certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNativeMulti',
    );
  }
  if (keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNativeMulti',
    );
  }

  final runtime = BridgeHttpRuntime(handler);
  final internalShutdown = Completer<void>();
  if (shutdownSignal != null) {
    // ignore: discarded_futures
    shutdownSignal.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  final futures = <Future<void>>[];
  for (var i = 0; i < binds.length; i++) {
    final bind = binds[i];
    final normalizedHost = _normalizeBindHost(bind.host, 'binds[$i].host');
    final future = _serveWithNativeProxy(
      host: normalizedHost,
      port: bind.port,
      secure: true,
      echo: false,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      requestClientCertificate: requestClientCertificate,
      http2: http2,
      http3: http3,
      nativeDirectCallback: nativeCallback,
      shutdownSignal: internalShutdown.future,
      tlsCertPath: certificatePath,
      tlsKeyPath: keyPath,
      tlsCertPassword: certificatePassword,
      handleFrame: (frame) async =>
          _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
      handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
        await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
      ),
      handleStream: runtime.handleStream,
    );
    futures.add(future);
    // Any listener completion (error or normal) should stop all listeners.
    // ignore: discarded_futures
    future.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  await Future.wait(futures);
}

/// Boots the Rust-native transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// [nativeCallback] defaults to `true`, which bypasses the bridge socket and
/// delivers requests through the native callback transport while keeping
/// `HttpRequest`/`HttpResponse` compatibility.
/// Set [nativeCallback] to `false` to use bridge socket transport.
///
/// {@macro server_native_serve_http_handler_example}
Future<void> serveNativeHttp(
  BridgeHttpHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
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
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native TLS transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// [nativeCallback] defaults to `true`, which bypasses the bridge socket and
/// delivers requests through the native callback transport while keeping
/// `HttpRequest`/`HttpResponse` compatibility.
/// Set [nativeCallback] to `false` to use bridge socket transport.
///
/// {@macro server_native_serve_http_handler_example}
Future<void> serveSecureNativeHttp(
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
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNativeHttp',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNativeHttp',
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
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native transport and dispatches requests directly to [handler]
/// without `HttpRequest`/`HttpResponse` wrapper allocation.
///
/// {@macro server_native_direct_handler_example}
Future<void> serveNativeDirect(
  NativeDirectHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeDirect = false,
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
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeDirect,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) => _handleDirectFrame(handler, frame),
    handlePayload: (payload) => _handleDirectPayload(handler, payload),
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
/// [handler] without `HttpRequest`/`HttpResponse` wrapper allocation.
///
/// {@macro server_native_direct_handler_example}
Future<void> serveSecureNativeDirect(
  NativeDirectHandler handler, {
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeDirect = false,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNativeDirect',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNativeDirect',
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
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeDirect,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: (frame) => _handleDirectFrame(handler, frame),
    handlePayload: (payload) => _handleDirectPayload(handler, payload),
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

final class _ProxyConnectionCounters {
  int _openSockets = 0;
  int _activeRequests = 0;

  void onSocketOpened() {
    _openSockets++;
  }

  void onSocketClosed() {
    if (_openSockets > 0) {
      _openSockets--;
    }
    if (_activeRequests > _openSockets) {
      _activeRequests = _openSockets;
    }
  }

  void onRequestStarted() {
    _activeRequests++;
  }

  void onRequestCompleted() {
    if (_activeRequests > 0) {
      _activeRequests--;
    }
  }

  HttpConnectionsInfo snapshot() {
    final info = HttpConnectionsInfo();
    info.total = _openSockets;
    info.active = _activeRequests;
    info.idle = _openSockets - _activeRequests;
    info.closing = 0;
    return info;
  }
}

final class _RunningProxy {
  _RunningProxy({
    required this.host,
    required this.port,
    required Future<void> Function({bool force}) close,
    required this.done,
    required this.connectionsInfo,
  }) : _close = close;

  final String host;
  final int port;
  final Future<void> Function({bool force}) _close;
  final Future<void> done;
  final HttpConnectionsInfo Function() connectionsInfo;

  Future<void> close({bool force = false}) => _close(force: force);
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
  required bool http2,
  required bool http3,
  bool nativeDirectCallback = false,
  required _BridgeHandleFrame handleFrame,
  required _BridgeHandleStream handleStream,
  _BridgeHandlePayload? handlePayload,
  void Function()? onEcho,
  Future<void>? shutdownSignal,
  String? tlsCertPath,
  String? tlsKeyPath,
  String? tlsCertPassword,
}) async {
  final running = await _startNativeProxy(
    host: host,
    port: port,
    secure: secure,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeDirectCallback,
    handleFrame: handleFrame,
    handleStream: handleStream,
    handlePayload: handlePayload,
    onEcho: onEcho,
    shutdownSignal: shutdownSignal,
    tlsCertPath: tlsCertPath,
    tlsKeyPath: tlsKeyPath,
    tlsCertPassword: tlsCertPassword,
    installSignalHandlers: true,
  );
  await running.done;
}

Future<_RunningProxy> _startNativeProxy({
  required String host,
  required int port,
  required bool secure,
  required bool echo,
  required int backlog,
  required bool v6Only,
  required bool shared,
  required bool requestClientCertificate,
  required bool http2,
  required bool http3,
  bool nativeDirectCallback = false,
  required _BridgeHandleFrame handleFrame,
  required _BridgeHandleStream handleStream,
  _BridgeHandlePayload? handlePayload,
  void Function()? onEcho,
  Future<void>? shutdownSignal,
  String? tlsCertPath,
  String? tlsKeyPath,
  String? tlsCertPassword,
  bool installSignalHandlers = true,
  _ProxyConnectionCounters? connectionCounters,
  Duration? Function()? idleTimeoutProvider,
}) async {
  // Ensure native symbol resolution and ABI compatibility are available.
  final abiVersion = transportAbiVersion();
  if (abiVersion <= 0) {
    throw StateError('Invalid server_native native ABI version: $abiVersion');
  }

  onEcho?.call();

  final enableHttp3 = secure && http3;
  final enableHttp2 = http2;
  if (http3 && !secure) {
    stderr.writeln(
      '[server_native] http3=true requested for insecure server; HTTP/3 requires TLS and will be disabled.',
    );
  }

  _BridgeBinding? bridgeBinding;
  StreamSubscription<Socket>? bridgeSubscription;
  late final NativeProxyServer proxy;
  try {
    if (nativeDirectCallback) {
      final directPayloadHandler = handlePayload;
      if (directPayloadHandler == null) {
        throw StateError(
          'nativeDirectCallback requires a payload-based direct handler',
        );
      }

      final nativeDirectStreams = <int, _NativeDirectRequestStreamState>{};
      late final NativeProxyServer proxyRef;
      proxy = NativeProxyServer.start(
        host: host,
        port: port,
        backendHost: InternetAddress.loopbackIPv4.address,
        backendPort: 9,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        requestClientCertificate: requestClientCertificate,
        enableHttp2: enableHttp2,
        enableHttp3: enableHttp3,
        tlsCertPath: tlsCertPath,
        tlsKeyPath: tlsKeyPath,
        tlsCertPassword: tlsCertPassword,
        directRequestCallback: (requestId, payload, payloadLen) {
          final requestPayload = Uint8List.fromList(
            payload.asTypedList(payloadLen),
          );

          void pushResponsePayload(Uint8List responsePayload) {
            final pushed = proxyRef.pushDirectResponseFrame(
              requestId,
              responsePayload,
            );
            if (!pushed) {
              stderr.writeln(
                '[server_native] native direct callback push failed for requestId=$requestId',
              );
            }
          }

          Future<void> removeNativeDirectStream({
            required _NativeDirectRequestStreamState streamState,
            bool closeDetachedSocket = true,
          }) async {
            final removed = nativeDirectStreams.remove(requestId);
            if (!identical(removed, streamState)) {
              return;
            }
            if (!streamState.requestBody.isClosed) {
              await streamState.requestBody.close();
            }
            if (closeDetachedSocket) {
              final detachedSocket = streamState.detachedSocket;
              if (detachedSocket != null) {
                await detachedSocket.close();
              }
            }
          }

          if (BridgeRequestFrame.isStartPayload(requestPayload)) {
            BridgeRequestFrame startFrame;
            try {
              startFrame = BridgeRequestFrame.decodeStartPayload(
                requestPayload,
              );
            } catch (error, stack) {
              stderr.writeln(
                '[server_native] native direct callback handler error: $error\n$stack',
              );
              pushResponsePayload(_encodeDirectBadRequestPayload(error));
              return;
            }

            final requestBody = StreamController<Uint8List>(sync: true);
            final streamState = _NativeDirectRequestStreamState(requestBody);
            nativeDirectStreams[requestId] = streamState;

            unawaited(() async {
              var keepStreamState = false;
              try {
                await handleStream(
                  frame: startFrame,
                  bodyStream: requestBody.stream,
                  onResponseStart: (frame) async {
                    streamState.detachedSocket = frame.detachedSocket;
                    pushResponsePayload(frame.encodeStartPayload());
                  },
                  onResponseChunk: (chunkBytes) async {
                    if (chunkBytes.isEmpty) {
                      return;
                    }
                    pushResponsePayload(
                      BridgeResponseFrame.encodeChunkPayload(chunkBytes),
                    );
                  },
                );
                pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
                final detachedSocket = streamState.detachedSocket;
                if (detachedSocket != null) {
                  keepStreamState = true;
                  unawaited(() async {
                    try {
                      await for (final chunk in detachedSocket.bridgeSocket) {
                        if (chunk.isEmpty) {
                          continue;
                        }
                        pushResponsePayload(
                          BridgeTunnelFrame.encodeChunkPayload(chunk),
                        );
                      }
                    } catch (_) {
                      // Peer closure and write errors both end the tunnel.
                    } finally {
                      if (identical(
                        nativeDirectStreams[requestId],
                        streamState,
                      )) {
                        pushResponsePayload(
                          BridgeTunnelFrame.encodeClosePayload(),
                        );
                      }
                      await removeNativeDirectStream(
                        streamState: streamState,
                        closeDetachedSocket: true,
                      );
                    }
                  }());
                }
              } catch (error, stack) {
                stderr.writeln(
                  '[server_native] native direct callback stream handler error: $error\n$stack',
                );
                pushResponsePayload(
                  _internalServerErrorFrame(error).encodePayload(),
                );
              } finally {
                if (!keepStreamState) {
                  await removeNativeDirectStream(
                    streamState: streamState,
                    closeDetachedSocket: true,
                  );
                }
              }
            }());
            return;
          }

          final streamState = nativeDirectStreams[requestId];
          if (streamState != null) {
            if (BridgeRequestFrame.isChunkPayload(requestPayload)) {
              try {
                final chunk = BridgeRequestFrame.decodeChunkPayload(
                  requestPayload,
                );
                if (chunk.isNotEmpty) {
                  streamState.requestBody.add(chunk);
                }
              } catch (error) {
                streamState.requestBody.addError(error);
                unawaited(streamState.requestBody.close());
              }
              return;
            }
            if (BridgeRequestFrame.isEndPayload(requestPayload)) {
              try {
                BridgeRequestFrame.decodeEndPayload(requestPayload);
              } catch (error) {
                streamState.requestBody.addError(error);
              }
              unawaited(streamState.requestBody.close());
              return;
            }

            final detachedSocket = streamState.detachedSocket;
            if (detachedSocket != null) {
              if (BridgeTunnelFrame.isChunkPayload(requestPayload)) {
                Uint8List chunkBytes;
                try {
                  chunkBytes = BridgeTunnelFrame.decodeChunkPayload(
                    requestPayload,
                  );
                } catch (error) {
                  stderr.writeln(
                    '[server_native] invalid native direct tunnel chunk for requestId=$requestId: $error',
                  );
                  unawaited(
                    removeNativeDirectStream(
                      streamState: streamState,
                      closeDetachedSocket: true,
                    ),
                  );
                  return;
                }
                if (chunkBytes.isNotEmpty) {
                  detachedSocket.bridgeSocket.add(chunkBytes);
                }
                return;
              }

              if (BridgeTunnelFrame.isClosePayload(requestPayload)) {
                try {
                  BridgeTunnelFrame.decodeClosePayload(requestPayload);
                } catch (_) {}
                unawaited(
                  removeNativeDirectStream(
                    streamState: streamState,
                    closeDetachedSocket: true,
                  ),
                );
                return;
              }
            }

            streamState.requestBody.addError(
              const FormatException(
                'unexpected frame while reading native direct request stream',
              ),
            );
            unawaited(streamState.requestBody.close());
            return;
          }

          if (BridgeRequestFrame.isChunkPayload(requestPayload) ||
              BridgeRequestFrame.isEndPayload(requestPayload) ||
              BridgeTunnelFrame.isChunkPayload(requestPayload) ||
              BridgeTunnelFrame.isClosePayload(requestPayload)) {
            stderr.writeln(
              '[server_native] dropping unmatched native direct frame for requestId=$requestId',
            );
            return;
          }

          unawaited(() async {
            _BridgeHandleFrameResult result;
            try {
              result = await directPayloadHandler(requestPayload);
            } catch (error, stack) {
              stderr.writeln(
                '[server_native] native direct callback handler error: $error\n$stack',
              );
              result = _BridgeHandleFrameResult.frame(
                _internalServerErrorFrame(error),
              );
            }
            final responsePayload =
                result.encodedPayload ?? result.frame.encodePayload();
            pushResponsePayload(responsePayload);
          }());
        },
      );
      proxyRef = proxy;
    } else {
      bridgeBinding = await _bindBridgeServer();
      final bridgeServer = bridgeBinding.server;
      bridgeSubscription = bridgeServer.listen((socket) {
        connectionCounters?.onSocketOpened();
        try {
          socket.setOption(SocketOption.tcpNoDelay, true);
        } catch (_) {}
        // ignore: discarded_futures
        _handleBridgeSocket(
          socket,
          handleFrame: handleFrame,
          handleStream: handleStream,
          handlePayload: handlePayload,
          idleTimeoutProvider: idleTimeoutProvider,
          onRequestStarted: connectionCounters?.onRequestStarted,
          onRequestCompleted: connectionCounters?.onRequestCompleted,
          onSocketClosed: connectionCounters?.onSocketClosed,
        );
      });

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
        enableHttp2: enableHttp2,
        enableHttp3: enableHttp3,
        tlsCertPath: tlsCertPath,
        tlsKeyPath: tlsKeyPath,
        tlsCertPassword: tlsCertPassword,
      );
    }
  } catch (error) {
    if (bridgeSubscription != null) {
      await bridgeSubscription.cancel();
    }
    if (bridgeBinding != null) {
      await bridgeBinding.dispose();
    }
    rethrow;
  }

  if (echo) {
    final scheme = secure ? 'https' : 'http';
    stdout.writeln(
      'Server listening on $scheme://$host:${proxy.port} via server_native '
      '(abi=$abiVersion, http2=$enableHttp2, http3=$enableHttp3)',
    );
  }

  final done = Completer<void>();
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  Timer? forceExitTimer;
  ProcessSignal? shutdownSignalSource;
  var stopping = false;

  Future<void> stopAll() async {
    if (done.isCompleted || stopping) return;
    stopping = true;
    forceExitTimer?.cancel();
    for (final subscription in signalSubscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    signalSubscriptions.clear();
    try {
      proxy.close();
    } catch (error, stack) {
      stderr.writeln('[server_native] proxy shutdown error: $error\n$stack');
    }
    try {
      if (bridgeSubscription != null) {
        await bridgeSubscription.cancel();
      }
    } catch (_) {}
    try {
      if (bridgeBinding != null) {
        await bridgeBinding.dispose();
      }
    } catch (_) {}
    if (!done.isCompleted) {
      done.complete();
    }
  }

  int forcedExitCode(ProcessSignal signal) {
    if (signal == ProcessSignal.sigterm) {
      return 143;
    }
    return 130;
  }

  void onProcessSignal(ProcessSignal signal) {
    if (shutdownSignalSource == null) {
      shutdownSignalSource = signal;
      stderr.writeln(
        '[server_native] received $signal, attempting graceful shutdown '
        '(send again to force exit).',
      );
      // ignore: discarded_futures
      stopAll();
      forceExitTimer = Timer(const Duration(seconds: 5), () {
        if (!done.isCompleted) {
          stderr.writeln(
            '[server_native] graceful shutdown timed out; forcing exit.',
          );
          exit(forcedExitCode(signal));
        }
      });
      return;
    }

    stderr.writeln('[server_native] forcing exit due to repeated signal.');
    exit(forcedExitCode(shutdownSignalSource!));
  }

  if (installSignalHandlers) {
    // Fallback signal handling when no external signal handling is provided.
    signalSubscriptions.add(
      ProcessSignal.sigint.watch().listen(onProcessSignal),
    );
    signalSubscriptions.add(
      ProcessSignal.sigterm.watch().listen(onProcessSignal),
    );
  }
  if (shutdownSignal != null) {
    // ignore: discarded_futures
    shutdownSignal.whenComplete(stopAll);
  }

  bridgeSubscription?.onDone(() {
    // ignore: discarded_futures
    stopAll();
  });

  return _RunningProxy(
    host: host,
    port: proxy.port,
    close: ({bool force = false}) {
      if (force) {
        proxy.close();
      }
      return stopAll();
    },
    done: done.future,
    connectionsInfo: () =>
        connectionCounters?.snapshot() ?? HttpConnectionsInfo(),
  );
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
        '[server_native] unix bridge bind failed ($path): $error; falling back to loopback tcp.',
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
  return '$tempDir/server_native_bridge_${pid}_$timestamp.sock';
}

Future<void> _handleBridgeSocket(
  Socket socket, {
  required _BridgeHandleFrame handleFrame,
  required _BridgeHandleStream handleStream,
  _BridgeHandlePayload? handlePayload,
  Duration? Function()? idleTimeoutProvider,
  void Function()? onRequestStarted,
  void Function()? onRequestCompleted,
  void Function()? onSocketClosed,
}) async {
  final reader = _SocketFrameReader(socket);
  final writer = _BridgeSocketWriter(socket);
  try {
    while (true) {
      Uint8List? firstPayload;
      try {
        firstPayload = await reader.readFrame(
          timeout: idleTimeoutProvider?.call(),
        );
      } on TimeoutException {
        return;
      }
      if (firstPayload == null) {
        return;
      }

      try {
        if (BridgeRequestFrame.isStartPayload(firstPayload)) {
          final startFrame = BridgeRequestFrame.decodeStartPayload(
            firstPayload,
          );
          onRequestStarted?.call();
          try {
            await _handleChunkedBridgeRequest(
              reader,
              writer,
              handleStream: handleStream,
              startFrame: startFrame,
            );
          } finally {
            onRequestCompleted?.call();
          }
          continue;
        }
      } catch (error) {
        _writeBridgeBadRequest(writer, error);
        continue;
      }

      onRequestStarted?.call();
      try {
        late final _BridgeHandleFrameResult response;
        if (handlePayload != null) {
          try {
            response = await handlePayload(firstPayload);
          } catch (error) {
            _writeBridgeBadRequest(writer, error);
            continue;
          }
        } else {
          BridgeRequestFrame frame;
          try {
            frame = BridgeRequestFrame.decodePayload(firstPayload);
          } catch (error) {
            _writeBridgeBadRequest(writer, error);
            continue;
          }
          response = await handleFrame(frame);
        }
        _writeBridgeResponse(writer, response);
        final detachedSocket = response.detachedSocket;
        if (detachedSocket != null) {
          await _runDetachedSocketTunnel(reader, writer, detachedSocket);
          return;
        }
      } finally {
        onRequestCompleted?.call();
      }
    }
  } catch (error, stack) {
    stderr.writeln('[server_native] bridge socket error: $error\n$stack');
  } finally {
    onSocketClosed?.call();
    await reader.cancel();
    try {
      await socket.flush();
    } catch (_) {}
    try {
      await socket.close();
    } catch (_) {}
  }
}

final Future<bool> _supportsIPv6 = () async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}();

final Future<bool> _supportsIPv4 = () async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}();

int _addressInUseErrorCode() {
  if (Platform.isWindows) {
    return 10048;
  }
  if (Platform.isMacOS) {
    return 48;
  }
  return 98;
}

bool _isAddressInUseSocketException(Object error) {
  if (error is! SocketException) {
    return false;
  }
  return error.osError?.errorCode == _addressInUseErrorCode();
}

Future<String> _anyHost() async {
  if (await _supportsIPv6) {
    return InternetAddress.anyIPv6.address;
  }
  return InternetAddress.anyIPv4.address;
}

Future<List<NativeServerBind>> _loopbackBinds(int port) async {
  final supportsV4 = await _supportsIPv4;
  final supportsV6 = await _supportsIPv6;

  if (!supportsV4 && !supportsV6) {
    throw StateError(
      'Neither IPv4 nor IPv6 loopback sockets are available on this host',
    );
  }

  final bindPort = (port == 0 && supportsV4 && supportsV6)
      ? await _reserveSharedLoopbackPort()
      : port;

  if (!supportsV4) {
    return <NativeServerBind>[
      NativeServerBind(
        host: InternetAddress.loopbackIPv6.address,
        port: bindPort,
      ),
    ];
  }
  if (!supportsV6) {
    return <NativeServerBind>[
      NativeServerBind(
        host: InternetAddress.loopbackIPv4.address,
        port: bindPort,
      ),
    ];
  }
  return <NativeServerBind>[
    NativeServerBind(
      host: InternetAddress.loopbackIPv4.address,
      port: bindPort,
    ),
    NativeServerBind(
      host: InternetAddress.loopbackIPv6.address,
      port: bindPort,
    ),
  ];
}

Future<int> _reserveSharedLoopbackPort({int retries = 5}) async {
  for (var attempt = 0; attempt <= retries; attempt++) {
    ServerSocket? v4Server;
    ServerSocket? v6Server;
    try {
      v4Server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final candidatePort = v4Server.port;
      v6Server = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        candidatePort,
      );
      return candidatePort;
    } on SocketException catch (error) {
      if (attempt == retries || !_isAddressInUseSocketException(error)) {
        rethrow;
      }
    } finally {
      if (v6Server != null) {
        await v6Server.close();
      }
      if (v4Server != null) {
        await v4Server.close();
      }
    }
  }
  throw StateError('unreachable');
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
      writer.writeChunkFrame(BridgeResponseFrame.chunkFrameType, chunkBytes);
    },
  );

  while (true) {
    try {
      final payload = await reader.readFrame();
      if (payload == null) {
        throw const FormatException('bridge stream ended before request end');
      }
      final payloadLength = payload.length;
      if (payloadLength < 2) {
        throw const FormatException('truncated bridge request frame header');
      }
      if (payload[0] != bridgeFrameProtocolVersion) {
        throw FormatException(
          'unsupported bridge protocol version: ${payload[0]}',
        );
      }

      final frameType = payload[1];
      if (frameType == BridgeRequestFrame.chunkFrameType) {
        if (payloadLength < 6) {
          throw const FormatException('truncated bridge request chunk payload');
        }
        final chunkLength = _readUint32BigEndian(payload, 2);
        if (payloadLength != chunkLength + 6) {
          throw const FormatException('truncated bridge request chunk payload');
        }
        if (chunkLength != 0) {
          requestBodyBytes += chunkLength;
          if (requestBodyBytes > _maxBridgeBodyBytes) {
            throw FormatException(
              'bridge request body too large: $requestBodyBytes',
            );
          }
          requestBody.add(Uint8List.sublistView(payload, 6, payloadLength));
        }
        continue;
      }
      if (frameType == BridgeRequestFrame.endFrameType) {
        if (payloadLength != 2) {
          throw const FormatException(
            'unexpected trailing bridge payload bytes: request end',
          );
        }
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

Future<_BridgeHandleFrameResult> _handleDirectFrame(
  NativeDirectHandler handler,
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
    if (response.encodedBridgePayload != null) {
      return _BridgeHandleFrameResult.encoded(response.encodedBridgePayload!);
    }
    if (response.bodyBytes != null) {
      return _BridgeHandleFrameResult.frame(
        BridgeResponseFrame(
          status: response.status,
          headers: response.headers,
          bodyBytes: response.bodyBytes!,
        ),
      );
    }
    final bodyBytes = await _collectDirectBodyBytes(response.body);
    return _BridgeHandleFrameResult.frame(
      BridgeResponseFrame(
        status: response.status,
        headers: response.headers,
        bodyBytes: bodyBytes,
      ),
    );
  } catch (error, stack) {
    stderr.writeln('[server_native] direct handler error: $error\n$stack');
    return _BridgeHandleFrameResult.frame(_internalServerErrorFrame(error));
  }
}

Future<_BridgeHandleFrameResult> _handleDirectPayload(
  NativeDirectHandler handler,
  Uint8List payload,
) async {
  try {
    final requestView = _DirectPayloadRequestView.parse(payload);
    final request = NativeDirectRequest._fromPayload(
      requestView,
      _lazyDirectPayloadBodyStream(requestView),
    );
    final response = await handler(request);
    if (response.encodedBridgePayload != null) {
      return _BridgeHandleFrameResult.encoded(response.encodedBridgePayload!);
    }
    if (response.bodyBytes != null) {
      return _BridgeHandleFrameResult.frame(
        BridgeResponseFrame(
          status: response.status,
          headers: response.headers,
          bodyBytes: response.bodyBytes!,
        ),
      );
    }
    final bodyBytes = await _collectDirectBodyBytes(response.body);
    return _BridgeHandleFrameResult.frame(
      BridgeResponseFrame(
        status: response.status,
        headers: response.headers,
        bodyBytes: bodyBytes,
      ),
    );
  } catch (error, stack) {
    stderr.writeln('[server_native] direct handler error: $error\n$stack');
    return _BridgeHandleFrameResult.frame(_internalServerErrorFrame(error));
  }
}

Stream<Uint8List> _lazyDirectPayloadBodyStream(
  _DirectPayloadRequestView requestView,
) {
  return _DirectPayloadBodyStream(requestView);
}

Future<void> _handleDirectStream(
  NativeDirectHandler handler, {
  required BridgeRequestFrame frame,
  required Stream<Uint8List> bodyStream,
  required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
  required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
}) async {
  var responseStarted = false;
  try {
    final request = _toDirectRequest(frame, bodyStream);
    final response = await handler(request);
    if (response.encodedBridgePayload != null) {
      final decoded = BridgeResponseFrame.decodePayload(
        response.encodedBridgePayload!,
      );
      await onResponseStart(
        BridgeResponseFrame(
          status: decoded.status,
          headers: decoded.headers,
          bodyBytes: Uint8List(0),
        ),
      );
      responseStarted = true;
      if (decoded.bodyBytes.isNotEmpty) {
        await onResponseChunk(decoded.bodyBytes);
      }
      return;
    }
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
    stderr.writeln(
      '[server_native] direct stream handler error: $error\n$stack',
    );
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

NativeDirectRequest _toDirectRequest(
  BridgeRequestFrame frame,
  Stream<Uint8List> bodyStream,
) {
  return NativeDirectRequest._fromFrame(frame, bodyStream);
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

Uint8List _encodeDirectBadRequestPayload(Object error) {
  return BridgeResponseFrame(
    status: HttpStatus.badRequest,
    headers: const <MapEntry<String, String>>[],
    bodyBytes: Uint8List.fromList(
      utf8.encode('invalid bridge request: $error'),
    ),
  ).encodePayload();
}

void _writeBridgeBadRequest(_BridgeSocketWriter writer, Object error) {
  final errorResponse = BridgeResponseFrame(
    status: HttpStatus.badRequest,
    headers: const <MapEntry<String, String>>[],
    bodyBytes: Uint8List.fromList(
      utf8.encode('invalid bridge request: $error'),
    ),
  );
  _writeBridgeResponse(writer, _BridgeHandleFrameResult.frame(errorResponse));
}

void _writeBridgeResponse(
  _BridgeSocketWriter writer,
  _BridgeHandleFrameResult response,
) {
  final encoded = response.encodedPayload;
  if (encoded != null) {
    writer.writeFrame(encoded);
    return;
  }
  writer.writeResponseFrame(response.frame);
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
    if (payload.isEmpty) {
      final prelude = Uint8List(4);
      _writeUint32BigEndian(prelude, 0, 0);
      _socket.add(prelude);
      return;
    }

    if (payload.length <= _coalescePayloadThresholdBytes) {
      final out = Uint8List(4 + payload.length);
      _writeUint32BigEndian(out, 0, payload.length);
      out.setRange(4, out.length, payload);
      _socket.add(out);
      return;
    }

    final prelude = Uint8List(4);
    _writeUint32BigEndian(prelude, 0, payload.length);
    _socket.add(prelude);
    _socket.add(payload);
  }

  void writeResponseFrame(BridgeResponseFrame response) {
    final body = response.bodyBytes;
    final prefix = response.encodePayloadPrefixWithoutBody();
    final payloadLength = prefix.length + body.length;
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge response frame too large: $payloadLength');
    }
    if (payloadLength <= _coalescePayloadThresholdBytes) {
      final out = Uint8List(4 + payloadLength);
      _writeUint32BigEndian(out, 0, payloadLength);
      out.setRange(4, 4 + prefix.length, prefix);
      if (body.isNotEmpty) {
        out.setRange(4 + prefix.length, out.length, body);
      }
      _socket.add(out);
      return;
    }

    final prelude = Uint8List(4 + prefix.length);
    _writeUint32BigEndian(prelude, 0, payloadLength);
    prelude.setRange(4, prelude.length, prefix);
    _socket.add(prelude);
    if (body.isNotEmpty) {
      _socket.add(body);
    }
  }

  void writeChunkFrame(int frameType, Uint8List chunkBytes) {
    final payloadLength = 6 + chunkBytes.length;
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge response frame too large: $payloadLength');
    }
    if (chunkBytes.length <= _coalescePayloadThresholdBytes) {
      final out = Uint8List(10 + chunkBytes.length);
      _writeUint32BigEndian(out, 0, payloadLength);
      out[4] = bridgeFrameProtocolVersion;
      out[5] = frameType & 0xff;
      _writeUint32BigEndian(out, 6, chunkBytes.length);
      if (chunkBytes.isNotEmpty) {
        out.setRange(10, out.length, chunkBytes);
      }
      _socket.add(out);
      return;
    }

    final prelude = Uint8List(10);
    _writeUint32BigEndian(prelude, 0, payloadLength);
    prelude[4] = bridgeFrameProtocolVersion;
    prelude[5] = frameType & 0xff;
    _writeUint32BigEndian(prelude, 6, chunkBytes.length);
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

@pragma('vm:prefer-inline')
void _writeUint32BigEndian(Uint8List buffer, int offset, int value) {
  buffer[offset] = (value >> 24) & 0xff;
  buffer[offset + 1] = (value >> 16) & 0xff;
  buffer[offset + 2] = (value >> 8) & 0xff;
  buffer[offset + 3] = value & 0xff;
}

@pragma('vm:prefer-inline')
int _readUint32BigEndian(Uint8List buffer, int offset) {
  return (buffer[offset] << 24) |
      (buffer[offset + 1] << 16) |
      (buffer[offset + 2] << 8) |
      buffer[offset + 3];
}

final class _ByteSlice {
  const _ByteSlice(this.start, this.end);

  final int start;
  final int end;
}

final class _ParsedField {
  const _ParsedField(this.slice, this.nextOffset);

  final _ByteSlice slice;
  final int nextOffset;
}

final class _DirectPayloadRequestView {
  _DirectPayloadRequestView._({
    required Uint8List payload,
    required bool tokenizedHeaderNames,
  }) : _payload = payload,
       _tokenizedHeaderNames = tokenizedHeaderNames;

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

  Future<Uint8List?> readFrame({Duration? timeout}) async {
    Future<Uint8List?> readOperation() async {
      final payloadLength = await _readUint32OrNull();
      if (payloadLength == null) {
        return null;
      }
      if (payloadLength > _maxBridgeFrameBytes) {
        throw FormatException('bridge frame too large: $payloadLength');
      }
      final payload = await _readExactOrNull(payloadLength);
      if (payload == null) {
        throw const FormatException('bridge stream ended before payload');
      }
      return payload;
    }

    if (timeout == null) {
      return readOperation();
    }
    return readOperation().timeout(timeout);
  }

  Future<void> cancel() => _iterator.cancel();

  Future<int?> _readUint32OrNull() async {
    final hasBytes = await _ensureAvailableOrNull(4);
    if (!hasBytes) {
      return null;
    }

    final first = _chunks.first;
    final start = _chunkOffset;
    final remainingInFirst = first.length - start;
    if (remainingInFirst >= 4) {
      final value = _readUint32BigEndian(first, start);
      _advanceFirstChunk(first, 4);
      return value;
    }

    final b0 = _consumeByte();
    final b1 = _consumeByte();
    final b2 = _consumeByte();
    final b3 = _consumeByte();
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }

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
        _advanceFirstChunk(first, count);
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
      _advanceFirstChunk(chunk, take);
    }
    return out;
  }

  @pragma('vm:prefer-inline')
  void _advanceFirstChunk(Uint8List chunk, int count) {
    _chunkOffset += count;
    _availableBytes -= count;
    if (_chunkOffset == chunk.length) {
      _chunks.removeFirst();
      _chunkOffset = 0;
    }
  }

  @pragma('vm:prefer-inline')
  int _consumeByte() {
    final chunk = _chunks.first;
    final value = chunk[_chunkOffset];
    _advanceFirstChunk(chunk, 1);
    return value;
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
