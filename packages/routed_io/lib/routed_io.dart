/// `dart:io` host transport for Routed.
///
/// Implements [RequestAdapter] / [ResponseAdapter] / [ServerTransport] for
/// process-hosted HTTP. Cloudflare Workers (and other hosts) ship a separate
/// package implementing the same core interfaces.
library;

export 'src/io_http_connection.dart' show IoHttpConnection;
export 'src/io_request_adapter.dart' show IoRequestAdapter;
export 'src/io_response_adapter.dart' show IoResponseAdapter;
export 'src/io_server_transport.dart' show IoServerTransport;
export 'src/server_boot.dart' show serveIo, serveSecureIo;
