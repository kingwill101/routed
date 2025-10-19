import 'dart:async';
import 'dart:io';

import 'package:server_testing/server_testing.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'shelf_translator.dart';

/// Adapter for Shelf's Handler that conforms to the RequestHandler interface.
///
/// This class allows you to use `server_testing` with Shelf applications by
/// implementing the [RequestHandler] interface. It converts between HttpRequest/HttpResponse
/// and shelf Request/Response objects.
///
/// ## Example
///
/// ```dart
/// import 'package:shelf/shelf.dart' as shelf;
/// import 'package:server_testing/server_testing.dart';
/// import 'package:server_testing_shelf/server_testing_shelf.dart';
///
/// void main() {
///   // A basic shelf application
///   final app = (request) {
///     if (request.url.path == 'hello') {
///       return shelf.Response.ok('Hello, World!');
///     }
///     return shelf.Response.notFound('Not found');
///   };
///
///   // Create the handler adapter
///   final handler = ShelfRequestHandler(app);
///
///   // Test with server_testing
///   engineTest('GET /hello returns greeting', (client) async {
///     final response = await client.get('/hello');
///     response
///       .assertStatus(200)
///       .assertBodyEquals('Hello, World!');
///   }, handler: handler);
/// }
/// ```
class ShelfRequestHandler implements RequestHandler {
  /// The Shelf handler function that will process requests.
  final shelf.Handler _handler;

  /// The HTTP server instance when using [TransportMode.ephemeralServer].
  HttpServer? _server;

  /// Creates a new handler that adapts a Shelf Handler to the RequestHandler interface.
  ///
  /// [handler] is the Shelf handler function that will process requests.
  ///
  /// Example:
  /// ```dart
  /// // Create a shelf handler
  /// final myApp = shelf.Pipeline()
  ///   .addMiddleware(shelf.logRequests())
  ///   .addHandler(_handleRequest);
  ///
  /// // Wrap it in ShelfRequestHandler
  /// final handler = ShelfRequestHandler(myApp);
  /// ```
  ShelfRequestHandler(shelf.Handler handler) : _handler = handler;

  /// Handles an HTTP request by delegating to the Shelf handler.
  ///
  /// This method transforms the [HttpRequest] into a Shelf [Request],
  /// passes it to the Shelf handler, and writes the resulting [Response]
  /// back to the [HttpResponse].
  @override
  Future<void> handleRequest(HttpRequest request) async {
    // Convert HttpRequest to shelf.Request
    final shelfRequest = await ShelfTranslator.httpRequestToShelfRequest(
      request,
    );

    // Process with shelf handler
    final shelfResponse = await _handler(shelfRequest);

    // Write the shelf Response back to the HttpResponse
    await ShelfTranslator.writeShelfResponseToHttpResponse(
      shelfResponse,
      request.response,
    );
  }

  /// Starts an HTTP server on the specified port.
  ///
  /// This method is called by server_testing when using the
  /// [TransportMode.ephemeralServer] mode. It binds an HTTP server to the
  /// given port and configures it to use the Shelf handler.
  ///
  /// [port] is the port to bind to (0 for random port)
  /// Returns the actual port number that the server is bound to.
  @override
  Future<int> startServer({int port = 0}) async {
    _server = await shelf_io.serve(
      _handler,
      InternetAddress.loopbackIPv4,
      port,
      poweredByHeader: 'server_testing_shelf',
      shared: true,
    );

    return _server!.port;
  }

  /// Closes the HTTP server if one was started.
  ///
  /// This method is called by server_testing when cleaning up resources after tests.
  /// [force] indicates whether to force close any active connections.
  @override
  Future<void> close([bool force = true]) async {
    await _server?.close(force: force);
    _server = null;
  }
}
