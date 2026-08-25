/// `dart:io` host transport for Routed applications.
///
/// This library binds a process-hosted [Engine] to a Dart VM HTTP server. It
/// maps `HttpRequest` and `HttpResponse` into Routed's host-neutral request,
/// response, and connection contracts while keeping the native fast path
/// available for streaming responses and WebSocket upgrades. Node and Workers
/// use their own host packages against the same core contracts.
///
/// The default boot path is [serveIo], which uses [IoHttpConnection] and
/// [Engine.handleConnection]. Use [dispatchIoExchange] or
/// [portableRequestFromIo] when a value-style boundary is more useful, such
/// as a custom server loop or host-parity test; this path delegates to
/// [Engine.handlePortable] and buffers the response before writing it.
///
/// ```dart
/// final engine = await Engine.create(providers: Engine.defaultProviders);
/// engine.get('/', (context) => context.string('hello'));
/// final server = await serveIo(engine, host: '127.0.0.1', port: 8080);
/// await server.close();
/// ```
library;

import 'package:routed_core/routed_core.dart' show Engine;
import 'package:routed_io/src/io_http_connection.dart' show IoHttpConnection;
import 'package:routed_io/src/io_portable.dart'
    show dispatchIoExchange, portableRequestFromIo;
import 'package:routed_io/src/server_boot.dart' show serveIo;

export 'src/io_http_connection.dart' show IoHttpConnection;
export 'src/io_portable.dart'
    show dispatchIoExchange, portableRequestFromIo, writePortableResponseToIo;
export 'src/io_request_adapter.dart' show IoRequestAdapter;
export 'src/io_response_adapter.dart' show IoResponseAdapter;
export 'src/io_server_transport.dart' show IoServerTransport;
export 'src/server_boot.dart' show serveIo, serveSecureIo;
