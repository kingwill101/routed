import 'package:routed_core/routed_core.dart';

import 'node_views.dart';

/// [RequestAdapter] backed by a Node.js [NodeIncomingView].
///
/// Does **not** implement [NativeRequestHandle] — portable hosts go through
/// [AdapterHttpBridge] inside [Engine.handleConnection].
final class NodeRequestAdapter implements RequestAdapter {
  NodeRequestAdapter(this.incoming, {Uri? baseUri})
    : uri = _resolveUri(incoming, baseUri),
      headers = _normalizeHeaders(incoming.rawHeaders);

  /// Underlying Node message view.
  final NodeIncomingView incoming;

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

  static Map<String, List<String>> _normalizeHeaders(
    Map<String, Object?> raw,
  ) {
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
