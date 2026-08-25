import 'dart:async';

import 'package:routed_core/routed_core.dart';

import 'node_request_adapter.dart';
import 'node_response_adapter.dart';
import 'node_views.dart';

/// Dispatches an upgraded Node socket through Routed's connection pipeline.
Future<void> dispatchNodeWebSocket(
  Engine engine,
  NodeRequestAdapter request,
  NodeWebSocketSocketView socket,
) async {
  final response = NodeResponseAdapter(_UpgradeResponseView(socket));
  await engine.handleConnection(HttpConnection(request, response));
}

final class _UpgradeResponseView implements NodeServerResponseView {
  _UpgradeResponseView(this.socket);
  final NodeWebSocketSocketView socket;
  bool _finished = false;

  @override
  void writeHead(int statusCode, Map<String, Object> headers) {}

  @override
  void write(List<int> bytes) {
    unawaited(socket.write(bytes));
  }

  @override
  void end([List<int>? bytes]) {
    _finished = true;
    unawaited(socket.end(bytes));
  }

  @override
  bool get finished => _finished;
}
