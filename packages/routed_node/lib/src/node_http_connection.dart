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
  /// Creates portable request and response adapters for one Node exchange.
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

  /// Host-specific context carried by the request, when supplied.
  final RoutedNodeContext? hostContext;

  /// Request adapter backed by the incoming Node message.
  final NodeRequestAdapter requestAdapter;

  /// Response adapter backed by the outgoing Node response.
  final NodeResponseAdapter responseAdapter;

  /// Connection passed to [Engine.handleConnection].
  HttpConnection get connection =>
      HttpConnection(requestAdapter, responseAdapter);
}
