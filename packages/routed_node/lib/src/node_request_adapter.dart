import 'package:routed_core/routed_core.dart';

import 'node_views.dart';
import 'runtime/runtime.dart';

/// [RequestAdapter] backed by a Node.js [NodeIncomingView].
///
/// Does **not** implement [NativeRequestHandle] — portable hosts go through
/// [AdapterHttpBridge] inside [Engine.handleConnection].
final class NodeRequestAdapter
    implements RequestAdapter, WebSocketUpgradeRequest, HostContextCarrier {
  /// Creates an adapter over a Node incoming message.
  NodeRequestAdapter(
    this.incoming, {
    Uri? baseUri,
    this.hostContext,
    this.isWebSocketUpgrade = false,
    this.acceptWebSocket,
    this.upgradeResponse,
  }) : uri = _resolveUri(incoming, baseUri),
       headers = _normalizeHeaders(incoming.rawHeaders);

  /// Underlying Node message view.
  final NodeIncomingView incoming;

  @override
  final RoutedNodeContext? hostContext;

  @override
  final bool isWebSocketUpgrade;

  /// Accepts a WebSocket upgrade when the listener supplied an acceptor.
  final Future<RoutedWebSocket> Function()? acceptWebSocket;

  /// Native handshake data populated when [accept] is called.
  final Object? Function()? upgradeResponse;

  @override
  Object? get nativeUpgradeResponse => upgradeResponse?.call();

  @override
  Future<RoutedWebSocket> accept() => acceptWebSocket == null
      ? throw UnsupportedError(
          'Node WebSocket upgrade requires the Node listener.',
        )
      : acceptWebSocket!();

  @override
  String get method => incoming.method.isEmpty ? 'GET' : incoming.method;

  @override
  final Uri uri;

  @override
  final Map<String, List<String>> headers;

  @override
  Stream<List<int>> get body => incoming.body;

  @override
  String? get remoteAddress => incoming.remoteAddress;

  static Uri _resolveUri(NodeIncomingView incoming, Uri? baseUri) {
    final raw = incoming.url.isEmpty ? '/' : incoming.url;
    final base = baseUri ?? Uri(scheme: 'http', host: 'localhost');
    return base.resolve(raw);
  }

  static Map<String, List<String>> _normalizeHeaders(Map<String, Object?> raw) {
    final out = <String, List<String>>{};
    raw.forEach((name, value) {
      if (value == null) return;
      final key = name.toLowerCase();
      if (value is List) {
        out[key] = value.map((e) => e.toString()).toList(growable: false);
      } else {
        out[key] = [value.toString()];
      }
    });
    return out;
  }
}
