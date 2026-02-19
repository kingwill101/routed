import 'dart:async';
import 'dart:typed_data';

import 'package:routed/routed.dart';
import 'package:server_native/src/bridge/bridge_runtime.dart';

/// Routed-specific adapter that dispatches bridge requests through an [Engine].
final class RoutedBridgeRuntime {
  RoutedBridgeRuntime(Engine engine)
    : _runtime = BridgeHttpRuntime(engine.handleRequest);

  final BridgeHttpRuntime _runtime;

  Future<void> handleStream({
    required BridgeRequestFrame frame,
    required Stream<Uint8List> bodyStream,
    required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
    required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
  }) {
    return _runtime.handleStream(
      frame: frame,
      bodyStream: bodyStream,
      onResponseStart: onResponseStart,
      onResponseChunk: onResponseChunk,
    );
  }

  Future<BridgeResponseFrame> handleFrame(BridgeRequestFrame frame) {
    return _runtime.handleFrame(frame);
  }
}

/// Backward-compatible alias for the previous runtime type name.
typedef BridgeRuntime = RoutedBridgeRuntime;
