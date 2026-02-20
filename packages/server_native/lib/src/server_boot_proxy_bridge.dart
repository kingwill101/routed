part of 'server_boot.dart';

/// Tracks open sockets and in-flight request counts for a proxy runtime.
///
/// Used to implement `HttpServer.connectionsInfo()` semantics on top of the
/// native transport listener(s).
final class _ProxyConnectionCounters {
  int _openSockets = 0;
  int _activeRequests = 0;

  /// Records a newly accepted backend bridge socket.
  void onSocketOpened() {
    _openSockets++;
  }

  /// Records socket close and clamps active request count.
  void onSocketClosed() {
    if (_openSockets > 0) {
      _openSockets--;
    }
    if (_activeRequests > _openSockets) {
      _activeRequests = _openSockets;
    }
  }

  /// Records request dispatch start for one bridge frame.
  void onRequestStarted() {
    _activeRequests++;
  }

  /// Records request dispatch completion.
  void onRequestCompleted() {
    if (_activeRequests > 0) {
      _activeRequests--;
    }
  }

  /// Returns a current [HttpConnectionsInfo] snapshot.
  HttpConnectionsInfo snapshot() {
    final info = HttpConnectionsInfo();
    info.total = _openSockets;
    info.active = _activeRequests;
    info.idle = _openSockets - _activeRequests;
    info.closing = 0;
    return info;
  }
}

/// Binds the local bridge transport server used for Rust <-> Dart frames.
///
/// On Unix this prefers a Unix-domain socket, falling back to loopback TCP.
/// On non-Unix hosts this always uses loopback TCP.
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

/// Returns the temporary Unix-domain socket path used for bridge transport.
String _bridgeUnixSocketPath() {
  final tempDir = Directory.systemTemp.path;
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '$tempDir/server_native_bridge_${pid}_$timestamp.sock';
}

/// Handles one accepted bridge socket from the native Rust transport.
///
/// This function decodes request frames, dispatches to Dart handlers, encodes
/// response frames, and runs tunnel mode for upgraded/detached sockets.
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
