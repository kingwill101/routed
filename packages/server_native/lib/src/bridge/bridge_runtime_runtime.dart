part of 'bridge_runtime.dart';

typedef BridgeHttpHandler = FutureOr<void> Function(BridgeHttpRequest request);

/// Handles bridge request frames with a `dart:io`-style [HttpRequest] handler.
///
/// {@macro server_native_bridge_runtime_example}
final class BridgeHttpRuntime {
  BridgeHttpRuntime(this._handler);

  final FutureOr<void> Function(BridgeHttpRequest request) _handler;

  /// Handles chunked request bodies and emits a chunked bridge response.
  Future<void> handleStream({
    required BridgeRequestFrame frame,
    required Stream<Uint8List> bodyStream,
    required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
    required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
  }) async {
    final response = BridgeStreamingHttpResponse(
      onStart: onResponseStart,
      onChunk: onResponseChunk,
    );
    final request = BridgeHttpRequest(
      frame: frame,
      response: response,
      bodyStream: bodyStream,
    );
    await _handler(request);
    if (!response.isClosed) {
      await response.close();
    }
    await response.done;
  }

  /// Handles a full single-frame request and returns a full response frame.
  Future<BridgeResponseFrame> handleFrame(BridgeRequestFrame frame) async {
    final response = BridgeHttpResponse();
    final request = BridgeHttpRequest(
      frame: frame,
      response: response,
      bodyStream: frame.bodyBytes.isEmpty
          ? const Stream<Uint8List>.empty()
          : Stream<Uint8List>.value(frame.bodyBytes),
    );
    await _handler(request);
    await response.done;

    final headerCount = response.flattenedHeaderCount;
    final headerNames = headerCount == 0
        ? const <String>[]
        : List<String>.filled(headerCount, '', growable: false);
    final headerValues = headerCount == 0
        ? const <String>[]
        : List<String>.filled(headerCount, '', growable: false);
    if (headerCount != 0) {
      response.writeFlattenedHeaders(headerNames, headerValues);
    }

    return BridgeResponseFrame.fromHeaderPairs(
      status: response.statusCode,
      headerNames: headerNames,
      headerValues: headerValues,
      bodyBytes: response.takeBodyBytes(),
      detachedSocket: response.takeDetachedSocket(),
    );
  }
}
