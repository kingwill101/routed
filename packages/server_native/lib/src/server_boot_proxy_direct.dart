part of 'server_boot.dart';

/// State holder for in-flight native direct stream requests.
final class _NativeDirectRequestStreamState {
  _NativeDirectRequestStreamState(
    this.requestBody, {
    required this.onTrackedClose,
  });

  final StreamController<Uint8List> requestBody;
  final void Function() onTrackedClose;
  BridgeDetachedSocket? detachedSocket;
  int responseStatusCode = HttpStatus.ok;
  bool detachedSocketUsesTunnel = false;
  final List<Uint8List> _pendingUnconsumedBodyChunks = <Uint8List>[];
  bool requestEnded = false;
  bool responseCompleted = false;
  bool _trackedClosed = false;

  void closeTrackedRequest() {
    if (_trackedClosed) {
      return;
    }
    _trackedClosed = true;
    onTrackedClose();
  }

  void maybeBufferUnconsumedRequestChunk(Uint8List chunk) {
    if (chunk.isEmpty) {
      return;
    }
    if (detachedSocket != null || requestBody.hasListener) {
      return;
    }
    _pendingUnconsumedBodyChunks.add(chunk);
  }

  void flushBufferedChunksToDetachedSocket() {
    final socket = detachedSocket;
    if (socket == null || _pendingUnconsumedBodyChunks.isEmpty) {
      return;
    }
    for (final chunk in _pendingUnconsumedBodyChunks) {
      socket.bridgeSocket.add(chunk);
    }
    _pendingUnconsumedBodyChunks.clear();
  }

  void clearBufferedRequestChunks() {
    _pendingUnconsumedBodyChunks.clear();
  }
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
        _nativeVerboseLog(
          '[server_native] native direct callback push failed for requestId=$requestId',
        );
      }
    }

    Future<void> forwardDetachedOutput(
      BridgeDetachedSocket detachedSocket, {
      required void Function(Uint8List chunkBytes) emitChunk,
    }) async {
      final prefetched = detachedSocket.takePrefetchedTunnelBytes();
      if (prefetched != null && prefetched.isNotEmpty) {
        emitChunk(prefetched);
      }
      final bridgeIterator = detachedSocket.bridgeIterator();
      while (await bridgeIterator.moveNext()) {
        final chunk = bridgeIterator.current;
        if (chunk.isEmpty) {
          continue;
        }
        emitChunk(chunk);
      }
    }

    Future<void> removeNativeDirectStream({
      required _NativeDirectRequestStreamState streamState,
      bool closeDetachedSocket = true,
      bool closeTrackedRequest = true,
    }) async {
      final removed = nativeDirectStreams.remove(requestId);
      if (!identical(removed, streamState)) {
        return;
      }
      if (!streamState.requestBody.isClosed) {
        await streamState.requestBody.close();
      }
      streamState.clearBufferedRequestChunks();
      if (closeDetachedSocket) {
        final detachedSocket = streamState.detachedSocket;
        if (detachedSocket != null) {
          await detachedSocket.close();
        }
      }
      if (closeTrackedRequest) {
        streamState.closeTrackedRequest();
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
      final streamState = _NativeDirectRequestStreamState(
        requestBody,
        onTrackedClose: endTrackedRequest,
      );
      nativeDirectStreams[requestId] = streamState;

      unawaited(() async {
        var keepStreamState = false;
        var detachedForwardingStarted = false;
        var responseStartSent = false;

        void startDetachedForwardingIfNeeded() {
          if (!responseStartSent) {
            return;
          }
          if (detachedForwardingStarted) {
            return;
          }
          final detachedSocket = streamState.detachedSocket;
          if (detachedSocket == null) {
            return;
          }
          detachedForwardingStarted = true;
          keepStreamState = true;
          final usesTunnel = streamState.detachedSocketUsesTunnel;
          unawaited(() async {
            try {
              if (usesTunnel) {
                pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
                await forwardDetachedOutput(
                  detachedSocket,
                  emitChunk: (chunk) {
                    pushResponsePayload(
                      BridgeTunnelFrame.encodeChunkPayload(chunk),
                    );
                  },
                );
              } else {
                await forwardDetachedOutput(
                  detachedSocket,
                  emitChunk: (chunk) {
                    pushResponsePayload(
                      BridgeResponseFrame.encodeChunkPayload(chunk),
                    );
                  },
                );
                pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
              }
            } catch (_) {
              // Peer closure and write errors both end the tunnel.
            } finally {
              if (usesTunnel &&
                  identical(nativeDirectStreams[requestId], streamState)) {
                pushResponsePayload(BridgeTunnelFrame.encodeClosePayload());
              }
              await removeNativeDirectStream(
                streamState: streamState,
                closeDetachedSocket: true,
                closeTrackedRequest: true,
              );
            }
          }());
        }

        try {
          await handleStream(
            frame: startFrame,
            bodyStream: requestBody.stream,
            onDetachedSocket: (socket) {
              streamState.detachedSocket = socket;
              streamState.flushBufferedChunksToDetachedSocket();
              startDetachedForwardingIfNeeded();
            },
            onResponseStart: (frame) async {
              responseStartSent = true;
              streamState.responseStatusCode = frame.status;
              streamState.detachedSocketUsesTunnel =
                  frame.status == HttpStatus.switchingProtocols;
              streamState.detachedSocket = frame.detachedSocket;
              streamState.flushBufferedChunksToDetachedSocket();
              pushResponsePayload(frame.encodeStartPayload());
              startDetachedForwardingIfNeeded();
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
          streamState.responseCompleted = true;
          if (streamState.detachedSocket != null) {
            startDetachedForwardingIfNeeded();
          } else {
            pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
            if (streamState.requestEnded) {
              await removeNativeDirectStream(
                streamState: streamState,
                closeDetachedSocket: true,
                closeTrackedRequest: true,
              );
            }
          }
        } catch (error, stack) {
          stderr.writeln(
            '[server_native] native direct callback stream handler error: $error\n$stack',
          );
          pushResponsePayload(_internalServerErrorFrame(error).encodePayload());
          streamState.responseCompleted = true;
          if (streamState.requestEnded && streamState.detachedSocket == null) {
            await removeNativeDirectStream(
              streamState: streamState,
              closeDetachedSocket: true,
              closeTrackedRequest: true,
            );
          }
        } finally {
          if (!keepStreamState &&
              streamState.requestEnded &&
              streamState.detachedSocket == null) {
            await removeNativeDirectStream(
              streamState: streamState,
              closeDetachedSocket: true,
              closeTrackedRequest: true,
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
          final chunk = BridgeRequestFrame.decodeChunkPayload(requestPayload);
          if (chunk.isNotEmpty) {
            final detachedSocket = streamState.detachedSocket;
            if (detachedSocket != null) {
              detachedSocket.bridgeSocket.add(chunk);
            } else {
              streamState.maybeBufferUnconsumedRequestChunk(chunk);
              streamState.requestBody.add(chunk);
            }
          }
        } catch (error) {
          streamState.requestBody.addError(error);
          streamState.requestEnded = true;
          unawaited(streamState.requestBody.close());
          if (streamState.responseCompleted &&
              streamState.detachedSocket == null) {
            unawaited(
              removeNativeDirectStream(
                streamState: streamState,
                closeDetachedSocket: true,
                closeTrackedRequest: true,
              ),
            );
          }
        }
        return;
      }
      if (BridgeRequestFrame.isEndPayload(requestPayload)) {
        try {
          BridgeRequestFrame.decodeEndPayload(requestPayload);
        } catch (error) {
          streamState.requestBody.addError(error);
        }
        streamState.requestEnded = true;
        unawaited(streamState.requestBody.close());
        if (streamState.responseCompleted &&
            streamState.detachedSocket == null) {
          unawaited(
            removeNativeDirectStream(
              streamState: streamState,
              closeDetachedSocket: true,
              closeTrackedRequest: true,
            ),
          );
        }
        return;
      }

      final detachedSocket = streamState.detachedSocket;
      if (detachedSocket != null && streamState.detachedSocketUsesTunnel) {
        if (BridgeTunnelFrame.isChunkPayload(requestPayload)) {
          Uint8List chunkBytes;
          try {
            chunkBytes = BridgeTunnelFrame.decodeChunkPayload(requestPayload);
          } catch (error) {
            _nativeVerboseLog(
              '[server_native] invalid native direct tunnel chunk for requestId=$requestId: $error',
            );
            unawaited(
              removeNativeDirectStream(
                streamState: streamState,
                closeDetachedSocket: true,
                closeTrackedRequest: true,
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
              closeTrackedRequest: true,
            ),
          );
          return;
        }
      }

      _nativeVerboseLog(
        '[server_native] dropping unexpected in-flight native direct request frame '
        'for requestId=$requestId',
      );
      return;
    }

    if (BridgeRequestFrame.isChunkPayload(requestPayload) ||
        BridgeRequestFrame.isEndPayload(requestPayload) ||
        BridgeTunnelFrame.isChunkPayload(requestPayload) ||
        BridgeTunnelFrame.isClosePayload(requestPayload)) {
      _nativeVerboseLog(
        '[server_native] dropping unmatched native direct frame for requestId=$requestId',
      );
      return;
    }

    unawaited(() async {
      beginTrackedRequest();
      try {
        BridgeRequestFrame? singleFrame;
        try {
          singleFrame = BridgeRequestFrame.decodePayload(requestPayload);
        } catch (_) {}

        if (singleFrame != null) {
          final bodyStream = singleFrame.bodyBytes.isEmpty
              ? const Stream<Uint8List>.empty()
              : Stream<Uint8List>.value(singleFrame.bodyBytes);
          BridgeDetachedSocket? detachedSocket;
          var detachedUsesTunnel = false;
          await handleStream(
            frame: singleFrame.copyWith(bodyBytes: Uint8List(0)),
            bodyStream: bodyStream,
            onDetachedSocket: (socket) {
              detachedSocket = socket;
            },
            onResponseStart: (frame) async {
              detachedUsesTunnel =
                  frame.status == HttpStatus.switchingProtocols;
              detachedSocket = frame.detachedSocket;
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
          if (detachedSocket != null) {
            try {
              if (detachedUsesTunnel) {
                pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
              }
              await forwardDetachedOutput(
                detachedSocket!,
                emitChunk: (chunk) {
                  pushResponsePayload(
                    detachedUsesTunnel
                        ? BridgeTunnelFrame.encodeChunkPayload(chunk)
                        : BridgeResponseFrame.encodeChunkPayload(chunk),
                  );
                },
              );
              if (detachedUsesTunnel) {
                pushResponsePayload(BridgeTunnelFrame.encodeClosePayload());
              } else {
                pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
              }
            } catch (_) {
              // Peer closure and write errors both end the tunnel.
            } finally {
              await detachedSocket!.close();
            }
          } else {
            pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
          }
          return;
        }

        final result = await directPayloadHandler(requestPayload);
        final responsePayload =
            result.encodedPayload ?? result.frame.encodePayload();
        pushResponsePayload(responsePayload);
      } catch (error, stack) {
        stderr.writeln(
          '[server_native] native direct callback handler error: $error\n$stack',
        );
        pushResponsePayload(_internalServerErrorFrame(error).encodePayload());
      } finally {
        endTrackedRequest();
      }
    }());
  }

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

  unawaited(() async {
    while (!proxyRef.isClosed) {
      NativeDirectRequestFrame? frame;
      try {
        // Use non-blocking native polling to avoid monopolizing the isolate
        // thread during websocket tunnel forwarding and teardown races.
        frame = proxyRef.pollDirectRequestFrame(timeoutMs: 0);
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
        await Future<void>.delayed(const Duration(milliseconds: 1));
        continue;
      }
      processRequestFrame(frame.requestId, frame.payload);
      await Future<void>.delayed(Duration.zero);
    }
  }());

  return proxy;
}
