import 'package:routed_core/routed_core.dart';

import 'node_request_adapter.dart';
import 'node_response_adapter.dart';
import 'node_views.dart';
import 'runtime/runtime.dart';

/// One Node.js HTTP exchange: [NodeIncomingView] + [NodeServerResponseView].
///
/// Exposes host-agnostic [HttpConnection] adapters for
/// [Engine.handleConnection].
final class NodeHttpConnection {
  NodeHttpConnection(
    NodeIncomingView incoming,
    NodeServerResponseView outgoing, {
    Uri? baseUri,
    this.hostContext,
  }) : requestAdapter = NodeRequestAdapter(
         incoming,
         baseUri: baseUri,
         hostContext: hostContext,
       ),
       responseAdapter = NodeResponseAdapter(outgoing);

  /// Host-specific context for this exchange.
  final RoutedNodeContext? hostContext;

  /// Portable request view.
  final NodeRequestAdapter requestAdapter;

  /// Portable response view.
  final NodeResponseAdapter responseAdapter;

  /// Core-facing connection pair.
  HttpConnection get connection =>
      HttpConnection(requestAdapter, responseAdapter);
}
