/// Node.js host transport for Routed.
///
/// Maps Node's `http` module into core portable messages / adapters.
/// Pair with `package:routed_core` (or batteries `package:routed`). Keep
/// separate from `package:routed_io` so VM and Node hosts stay independent.
///
/// Preferred path: `dispatchNodeExchange` / `Engine.handlePortable`.
/// Stream-sink path: `NodeHttpConnection` + `Engine.handleConnection`.
library;

export 'src/runtime/runtime.dart';
export 'src/runtime/lifecycle.dart';
export 'src/runtime/host_context.dart';
export 'src/fetch/fetch_exchange.dart';
export 'src/node_http_connection.dart' show NodeHttpConnection;
export 'src/node_portable.dart'
    show
        portableRequestFromNode,
        writePortableResponseToNode,
        dispatchNodeExchange;
export 'src/node_request_adapter.dart' show NodeRequestAdapter;
export 'src/node_response_adapter.dart' show NodeResponseAdapter;
export 'src/node_server_transport.dart' show NodeServerTransport;
export 'src/node_views.dart'
    show NodeIncomingView, NodeServerResponseView, NodeWebSocketSocketView;
export 'src/node_websocket.dart'
    show NodeRoutedWebSocket, NodeWebSocketUpgradeResponse;
export 'src/server_boot.dart' show serveNode;
