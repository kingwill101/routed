import 'package:routed_core/routed_core.dart';

import 'node_request_adapter.dart';
import 'node_response_adapter.dart';
import 'node_views.dart';

/// One Node.js HTTP exchange: [NodeIncomingView] + [NodeServerResponseView].
///
/// Exposes host-agnostic [HttpConnection] adapters for
/// [Engine.handleConnection].
final class NodeHttpConnection {
  NodeHttpConnection(
    NodeIncomingView incoming,
    NodeServerResponseView outgoing, {
    Uri? baseUri,
  }) : requestAdapter = NodeRequestAdapter(incoming, baseUri: baseUri),
       responseAdapter = NodeResponseAdapter(outgoing);

  /// Portable request view.
  final NodeRequestAdapter requestAdapter;

  /// Portable response view.
  final NodeResponseAdapter responseAdapter;

  /// Core-facing connection pair.
  HttpConnection get connection =>
      HttpConnection(requestAdapter, responseAdapter);
}
