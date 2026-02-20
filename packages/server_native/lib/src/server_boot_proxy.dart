part of 'server_boot.dart';

/// Runtime handle for one running native proxy bootstrap.
///
/// This internal wrapper normalizes lifecycle operations shared by:
/// - callback APIs (`serveNative*`)
/// - stream APIs (`NativeHttpServer` bindings)
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

  /// Requests proxy shutdown.
  Future<void> close({bool force = false}) => _close(force: force);
}

/// Boots a native proxy and waits until it exits.
///
/// This is the shared implementation behind all top-level `serveNative*`
/// entrypoints.
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

/// Starts the native proxy process, bridge server, and shutdown wiring.
///
/// Returns when startup is complete and the runtime is ready to accept traffic.
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
    _nativeVerboseLog(_http3RequiresTlsLogMessage);
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
      proxy = _startNativeDirectProxy(
        host: host,
        port: port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        requestClientCertificate: requestClientCertificate,
        enableHttp2: enableHttp2,
        enableHttp3: enableHttp3,
        tlsCertPath: tlsCertPath,
        tlsKeyPath: tlsKeyPath,
        tlsCertPassword: tlsCertPassword,
        directPayloadHandler: directPayloadHandler,
        handleStream: handleStream,
        onSocketOpened: connectionCounters?.onSocketOpened,
        onSocketClosed: connectionCounters?.onSocketClosed,
        onRequestStarted: connectionCounters?.onRequestStarted,
        onRequestCompleted: connectionCounters?.onRequestCompleted,
      );
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

  /// Attempts graceful shutdown across proxy and bridge resources.
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

  /// Maps process signals to conventional shell exit codes.
  int forcedExitCode(ProcessSignal signal) {
    if (signal == ProcessSignal.sigterm) {
      return 143;
    }
    return 130;
  }

  /// Handles signal-driven shutdown escalation.
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
