part of 'server_boot.dart';

/// State holder for in-flight native direct stream requests.
final class _NativeDirectRequestStreamState {
  _NativeDirectRequestStreamState(this.requestBody);

  final StreamController<Uint8List> requestBody;
  BridgeDetachedSocket? detachedSocket;
}

/// Starts the native callback transport path (no bridge socket backend).
NativeProxyServer _startNativeDirectProxy({
  required String host,
  required int port,
  required int backlog,
  required bool v6Only,
  required bool shared,
  required bool requestClientCertificate,
  required bool enableHttp2,
  required bool enableHttp3,
  required String? tlsCertPath,
  required String? tlsKeyPath,
  required String? tlsCertPassword,
  required _BridgeHandlePayload directPayloadHandler,
  required _BridgeHandleStream handleStream,
  void Function()? onSocketOpened,
  void Function()? onSocketClosed,
  void Function()? onRequestStarted,
  void Function()? onRequestCompleted,
}) {
  final nativeDirectStreams = <int, _NativeDirectRequestStreamState>{};
  late final NativeProxyServer proxyRef;
  final proxy = NativeProxyServer.start(
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
    directRequestCallback: null,
  );
  proxyRef = proxy;

  void processRequestFrame(int requestId, Uint8List requestPayload) {
    if (proxyRef.isClosed) {
      return;
    }

    void beginTrackedRequest() {
      onSocketOpened?.call();
      onRequestStarted?.call();
    }

    void endTrackedRequest() {
      onRequestCompleted?.call();
      onSocketClosed?.call();
    }

    void pushResponsePayload(Uint8List responsePayload) {
      if (proxyRef.isClosed) {
        return;
      }
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
        startFrame = BridgeRequestFrame.decodeStartPayload(requestPayload);
      } catch (error, stack) {
        stderr.writeln(
          '[server_native] native direct callback handler error: $error\n$stack',
        );
        pushResponsePayload(_encodeDirectBadRequestPayload(error));
        return;
      }
      beginTrackedRequest();

      final requestBody = StreamController<Uint8List>(sync: true);
      final streamState = _NativeDirectRequestStreamState(requestBody);
      nativeDirectStreams[requestId] = streamState;

      unawaited(() async {
        var keepStreamState = false;
        var requestClosed = false;
        void closeTrackedRequest() {
          if (requestClosed) {
            return;
          }
          requestClosed = true;
          endTrackedRequest();
        }

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
                final prefetched = detachedSocket.takePrefetchedTunnelBytes();
                if (prefetched != null && prefetched.isNotEmpty) {
                  pushResponsePayload(
                    BridgeTunnelFrame.encodeChunkPayload(prefetched),
                  );
                }
                final bridgeIterator = detachedSocket.bridgeIterator();
                while (await bridgeIterator.moveNext()) {
                  final chunk = bridgeIterator.current;
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
                if (identical(nativeDirectStreams[requestId], streamState)) {
                  pushResponsePayload(BridgeTunnelFrame.encodeClosePayload());
                }
                await removeNativeDirectStream(
                  streamState: streamState,
                  closeDetachedSocket: true,
                );
                closeTrackedRequest();
              }
            }());
          }
        } catch (error, stack) {
          stderr.writeln(
            '[server_native] native direct callback stream handler error: $error\n$stack',
          );
          pushResponsePayload(_internalServerErrorFrame(error).encodePayload());
        } finally {
          if (!keepStreamState) {
            await removeNativeDirectStream(
              streamState: streamState,
              closeDetachedSocket: true,
            );
            closeTrackedRequest();
          }
        }
      }());
      return;
    }

    final streamState = nativeDirectStreams[requestId];
    if (streamState != null) {
      if (BridgeRequestFrame.isChunkPayload(requestPayload)) {
        try {
          final chunk = BridgeRequestFrame.decodeChunkPayload(requestPayload);
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
            chunkBytes = BridgeTunnelFrame.decodeChunkPayload(requestPayload);
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
      beginTrackedRequest();
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
      try {
        pushResponsePayload(responsePayload);
      } finally {
        endTrackedRequest();
      }
    }());
  }

  unawaited(() async {
    while (!proxyRef.isClosed) {
      NativeDirectRequestFrame? frame;
      try {
        frame = proxyRef.pollDirectRequestFrame(timeoutMs: 100);
      } catch (error, stack) {
        stderr.writeln(
          '[server_native] native direct poll failed: $error\n$stack',
        );
        if (proxyRef.isClosed) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        continue;
      }
      if (frame == null) {
        await Future<void>.delayed(Duration.zero);
        continue;
      }
      processRequestFrame(frame.requestId, frame.payload);
      await Future<void>.delayed(Duration.zero);
    }
  }());

  return proxy;
}
