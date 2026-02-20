part of 'server_boot.dart';

/// Handles chunked/direct bridge request processing and direct payload parsing.
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

/// Handles a direct bridge request decoded as a [BridgeRequestFrame].
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

/// Handles a direct bridge request in compact payload form.
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

/// Lazily projects direct request payload bytes into a body stream.
Stream<Uint8List> _lazyDirectPayloadBodyStream(
  _DirectPayloadRequestView requestView,
) {
  return _DirectPayloadBodyStream(requestView);
}

/// Handles streamed direct requests and emits response start/chunk callbacks.
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

/// Converts a bridge frame/body stream pair into a [NativeDirectRequest].
NativeDirectRequest _toDirectRequest(
  BridgeRequestFrame frame,
  Stream<Uint8List> bodyStream,
) {
  return NativeDirectRequest._fromFrame(frame, bodyStream);
}

/// Builds a request URI from bridge request primitives.
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

/// Parsed host/port authority tuple.
final class _DirectAuthority {
  const _DirectAuthority({required this.host, required this.port});

  final String host;
  final int? port;
}

/// Splits an authority string into host/optional port.
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

/// Collects response body chunks into a single byte buffer.
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

/// Creates a generic 500 response frame for uncaught direct handler failures.
BridgeResponseFrame _internalServerErrorFrame(Object error) {
  return BridgeResponseFrame(
    status: HttpStatus.internalServerError,
    headers: const <MapEntry<String, String>>[
      MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
    ],
    bodyBytes: Uint8List.fromList(utf8.encode('direct handler error: $error')),
  );
}

/// Encodes a `400 Bad Request` bridge payload for direct payload parsing errors.
Uint8List _encodeDirectBadRequestPayload(Object error) {
  return BridgeResponseFrame(
    status: HttpStatus.badRequest,
    headers: const <MapEntry<String, String>>[],
    bodyBytes: Uint8List.fromList(
      utf8.encode('invalid bridge request: $error'),
    ),
  ).encodePayload();
}

/// Writes a `400 Bad Request` frame to the active bridge socket.
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

/// Writes either an encoded or structured bridge response to the socket.
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

/// Relays bytes between bridge tunnel frames and detached backend socket.
Future<void> _runDetachedSocketTunnel(
  _SocketFrameReader reader,
  _BridgeSocketWriter writer,
  BridgeDetachedSocket detachedSocket,
) async {
  final bridgeSocket = detachedSocket.bridgeSocket;
  final bridgeIterator = detachedSocket.bridgeIterator();

  final outboundTask = () async {
    try {
      final prefetched = detachedSocket.takePrefetchedTunnelBytes();
      if (prefetched != null && prefetched.isNotEmpty) {
        await writer.writeChunkFrameAndFlush(
          BridgeTunnelFrame.chunkFrameType,
          prefetched,
        );
      }
      while (await bridgeIterator.moveNext()) {
        final chunk = bridgeIterator.current;
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
