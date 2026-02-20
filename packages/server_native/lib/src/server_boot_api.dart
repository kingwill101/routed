part of 'server_boot.dart';

/// Internal callback contract for decoded bridge request frames.
typedef _BridgeHandleFrame =
    Future<_BridgeHandleFrameResult> Function(BridgeRequestFrame frame);

/// Internal callback contract for raw request payload frames.
///
/// Used by native callback mode to avoid decoding into [BridgeRequestFrame]
/// when handlers can process compact payloads directly.
typedef _BridgeHandlePayload =
    Future<_BridgeHandleFrameResult> Function(Uint8List payload);

/// Internal callback contract for streamed request/response frame handling.
typedef _BridgeHandleStream =
    Future<void> Function({
      required BridgeRequestFrame frame,
      required Stream<Uint8List> bodyStream,
      required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
      required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
    });
