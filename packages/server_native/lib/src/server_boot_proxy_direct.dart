part of 'server_boot.dart';

/// State holder for in-flight native direct stream requests.
final class _NativeDirectRequestStreamState {
  _NativeDirectRequestStreamState(
    this.requestBody, {
    required this.requestLease,
    required this.onSocketClosed,
  });

  final StreamController<Uint8List> requestBody;
  final _RequestLease? requestLease;
  final void Function() onSocketClosed;
  BridgeDetachedSocket? detachedSocket;
  int responseStatusCode = HttpStatus.ok;
  bool detachedSocketUsesTunnel = false;
  final List<Uint8List> _pendingUnconsumedBodyChunks = <Uint8List>[];
  bool requestEnded = false;
  bool responseCompleted = false;
  bool _trackedClosed = false;
  bool _requestCompletionNotified = false;
  bool _requestDetachNotified = false;

  void markRequestDetached() {
    if (_requestDetachNotified) {
      return;
    }
    _requestDetachNotified = true;
    requestLease?.detach();
  }

  void markRequestCompleted() {
    if (_requestCompletionNotified) {
      return;
    }
    _requestCompletionNotified = true;
    requestLease?.complete();
  }

  void closeTrackedRequest() {
    if (_trackedClosed) {
      return;
    }
    _trackedClosed = true;
    markRequestCompleted();
    onSocketClosed();
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
({
  NativeProxyServer proxy,
  Future<void> Function() closeStreams,
})
_startNativeDirectProxy({
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
  _RequestLease Function()? onRequestStarted,
}) {
  final nativeDirectStreams = <int, _NativeDirectRequestStreamState>{};
  late final NativeProxyServer proxyRef;
  var proxyAssigned = false;
  var drainQueuedFramesScheduled = false;
  var drainWakeRequested = false;

  void processRequestFrame(int requestId, Uint8List requestPayload) {
    final proxy = proxyRef;
    if (proxy.isClosed) {
      return;
    }

    _RequestLease? beginTrackedRequest() {
      onSocketOpened?.call();
      return onRequestStarted?.call();
    }

    void pushResponsePayload(Uint8List responsePayload) {
      if (proxy.isClosed) {
        return;
      }
      final pushed = proxy.pushDirectResponseFrame(requestId, responsePayload);
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
        // An unconsumed single-subscription body never completes its close
        // future. Shutdown must not wait for a handler that intentionally
        // ignored the request body.
        unawaited(streamState.requestBody.close());
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
      final requestLease = beginTrackedRequest();

      final requestBody = StreamController<Uint8List>(sync: true);
      final streamState = _NativeDirectRequestStreamState(
        requestBody,
        requestLease: requestLease,
        onSocketClosed: () => onSocketClosed?.call(),
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
              streamState.markRequestDetached();
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
          streamState.markRequestCompleted();
          if (streamState.detachedSocket != null) {
            startDetachedForwardingIfNeeded();
          } else {
            pushResponsePayload(BridgeResponseFrame.encodeEndPayload());
            if (streamState.requestEnded) {
              await removeNativeDirectStream(
                streamState: streamState,
              );
            }
          }
        } catch (error, stack) {
          stderr.writeln(
            '[server_native] native direct callback stream handler error: $error\n$stack',
          );
          pushResponsePayload(_internalServerErrorFrame().encodePayload());
          streamState.responseCompleted = true;
          streamState.markRequestCompleted();
          if (streamState.requestEnded && streamState.detachedSocket == null) {
            await removeNativeDirectStream(
              streamState: streamState,
            );
          }
        } finally {
          if (!keepStreamState &&
              streamState.requestEnded &&
              streamState.detachedSocket == null) {
            await removeNativeDirectStream(
              streamState: streamState,
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
      final requestLease = beginTrackedRequest();
      try {
        final result = await directPayloadHandler(requestPayload);
        final responsePayload =
            result.encodedPayload ?? result.frame.encodePayload();
        pushResponsePayload(responsePayload);
      } catch (error, stack) {
        stderr.writeln(
          '[server_native] native direct callback handler error: $error\n$stack',
        );
        pushResponsePayload(_internalServerErrorFrame().encodePayload());
      } finally {
        requestLease?.complete();
        onSocketClosed?.call();
      }
    }());
  }

  Future<void> closeStreams() async {
    final streams = nativeDirectStreams.values.toList(growable: false);
    nativeDirectStreams.clear();
    for (final streamState in streams) {
      if (!streamState.requestBody.isClosed) {
        // An unconsumed single-subscription body may never complete its close
        // future. Force shutdown must not wait for an abandoned request body.
        unawaited(streamState.requestBody.close());
      }
      streamState.clearBufferedRequestChunks();
      final detachedSocket = streamState.detachedSocket;
      if (detachedSocket != null) {
        detachedSocket.destroy();
      }
      streamState.closeTrackedRequest();
    }
  }

  void scheduleDrainQueuedRequestFrames() {
    drainWakeRequested = true;
    if (!proxyAssigned || drainQueuedFramesScheduled || proxyRef.isClosed) {
      return;
    }
    drainQueuedFramesScheduled = true;
    unawaited(() async {
      const retryDelayAfterPollError = Duration(milliseconds: 1);
      const maxFramesPerTurn = 32;

      try {
        while (!proxyRef.isClosed) {
          drainWakeRequested = false;
          var drainedFrames = 0;
          while (!proxyRef.isClosed && drainedFrames < maxFramesPerTurn) {
            NativeDirectRequestFrame? frame;
            try {
              frame = proxyRef.pollDirectRequestFrame(timeoutMs: 0);
            } catch (error, stack) {
              stderr.writeln(
                '[server_native] native direct poll failed: $error\n$stack',
              );
              if (proxyRef.isClosed) {
                return;
              }
              drainWakeRequested = true;
              await Future<void>.delayed(retryDelayAfterPollError);
              break;
            }

            if (frame == null) {
              break;
            }

            processRequestFrame(frame.requestId, frame.payload);
            drainedFrames++;
          }

          if (drainedFrames == maxFramesPerTurn) {
            // Keep callback mode responsive when a burst fills the queue.
            await Future<void>.delayed(Duration.zero);
            continue;
          }

          if (!drainWakeRequested) {
            break;
          }

          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        drainQueuedFramesScheduled = false;
        if (drainWakeRequested && !proxyRef.isClosed) {
          scheduleDrainQueuedRequestFrames();
        }
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
    // Rust queues callback payloads and uses this listener only as a wake-up
    // signal, so the Dart isolate does not need a hot polling loop.
    directRequestCallback: (requestId, payload) {
      scheduleDrainQueuedRequestFrames();
    },
  );
  proxyRef = proxy;
  proxyAssigned = true;
  if (drainWakeRequested) {
    scheduleDrainQueuedRequestFrames();
  }

  return (proxy: proxy, closeStreams: closeStreams);
}
