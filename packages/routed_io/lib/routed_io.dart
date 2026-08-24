/// `dart:io` host transport for Routed.
///
/// Process-hosted HTTP for the Dart VM. Maps `HttpRequest`/`HttpResponse` into
/// core adapters and portable messages. Node/Workers use separate packages.
///
/// - **Native fast path (default serve):** [IoHttpConnection] +
///   [Engine.handleConnection] (websockets, progressive writes).
/// - **Value edge:** `dispatchIoExchange` / `portableRequestFromIo` →
///   [Engine.handlePortable].
library;

import 'package:routed_core/routed_core.dart' show Engine;
import 'package:routed_io/src/io_http_connection.dart' show IoHttpConnection;

export 'src/io_http_connection.dart' show IoHttpConnection;
export 'src/io_portable.dart'
    show dispatchIoExchange, portableRequestFromIo, writePortableResponseToIo;
export 'src/io_request_adapter.dart' show IoRequestAdapter;
export 'src/io_response_adapter.dart' show IoResponseAdapter;
export 'src/io_server_transport.dart' show IoServerTransport;
export 'src/server_boot.dart' show serveIo, serveSecureIo;
