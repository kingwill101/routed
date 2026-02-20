part of 'bridge_runtime.dart';

/// Socket pair used to bridge upgraded protocol bytes over FFI frames.
final class BridgeDetachedSocket {
  BridgeDetachedSocket({
    required this.applicationSocket,
    required this.bridgeSocket,
  });

  /// Socket handed to Dart upgrade APIs (`WebSocketTransformer.upgrade`).
  final Socket applicationSocket;

  /// Peer socket retained by the bridge runtime for Rust tunnel forwarding.
  final Socket bridgeSocket;

  /// Closes both ends of the detached socket pair, ignoring close races.
  Future<void> close() async {
    try {
      await applicationSocket.close();
    } catch (_) {}
    try {
      await bridgeSocket.close();
    } catch (_) {}
  }
}

/// Creates a loopback socket pair used by `HttpResponse.detachSocket`.
Future<BridgeDetachedSocket> _createDetachedSocketPair() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final bridgeSocketFuture = listener.first;
    final applicationSocketFuture = Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );

    final bridgeSocket = await bridgeSocketFuture;
    final applicationSocket = await applicationSocketFuture;
    try {
      bridgeSocket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    try {
      applicationSocket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    return BridgeDetachedSocket(
      applicationSocket: applicationSocket,
      bridgeSocket: bridgeSocket,
    );
  } finally {
    await listener.close();
  }
}
