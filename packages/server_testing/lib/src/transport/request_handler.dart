import 'dart:io';

/// Defines the interface for handling HTTP requests.
///
/// This is the core abstraction that different server implementations will adapt to.
/// When using the server_testing package, you need to implement this interface
/// to handle requests from the testing client.
///
/// There are two main ways to implement this interface:
/// 1. Create a custom implementation for testing specific features
/// 2. Create an adapter for an existing web framework or application
///
/// ## Example Custom Implementation
///
/// ```dart
/// class SimpleJsonHandler implements RequestHandler {
///   final Map<String, dynamic> _data;
///
///   SimpleJsonHandler(this._data);
///
///   @override
///   Future<void> handleRequest(HttpRequest request) async {
///     final response = request.response;
///     response.statusCode = 200;
///     response.headers.contentType = ContentType.json;
///     response.write(jsonEncode(_data));
///     await response.close();
///   }
///
///   @override
///   Future<int> startServer({int port = 0}) async {
///     final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
///     server.listen(handleRequest);
///     return server.port;
///   }
///
///   @override
///   Future<void> close([bool force = true]) async {
///     // No resources to clean up in this simple handler
///   }
/// }
/// ```
///
/// ## Example Framework Adapter
///
/// ```dart
/// class MyFrameworkHandler implements RequestHandler {
///   final MyFramework framework;
///   HttpServer? _server;
///
///   MyFrameworkHandler(this.framework);
///
///   @override
///   Future<void> handleRequest(HttpRequest request) async {
///     return framework.processRequest(request);
///   }
///
///   @override
///   Future<int> startServer({int port = 0}) async {
///     _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
///     _server!.listen(handleRequest);
///     return _server!.port;
///   }
///
///   @override
///   Future<void> close([bool force = true]) async {
///     await _server?.close(force: force);
///     _server = null;
///   }
/// }
/// ```
abstract class RequestHandler {
  /// Handles an HTTP request directly.
  ///
  /// This method is called for both in-memory testing and server-based testing.
  /// For in-memory transport, this will be called with mock HttpRequest objects.
  /// For server transport, this will be called for actual HTTP requests.
  ///
  /// Your implementation should:
  /// - Process the request
  /// - Set appropriate status codes and headers on the response
  /// - Write response data if needed
  /// - Close the response
  ///
  /// [request] is the HTTP request to handle.
  Future<void> handleRequest(HttpRequest request);

  /// Starts a server on the given port (for server-based transports).
  ///
  /// This method is called only when using the [TransportMode.ephemeralServer] mode.
  /// It should start an HTTP server that uses the [handleRequest] method to
  /// process incoming requests.
  ///
  /// [port] is the port to bind to (0 for random port)
  /// Returns the bound port number.
  Future<int> startServer({int port = 0});

  /// Releases any resources used by this handler.
  ///
  /// This method is called when the test client is closed.
  /// It should clean up any resources used by the handler,
  /// such as closing server connections.
  ///
  /// [force] indicates whether to force close any active connections.
  Future<void> close([bool force = true]);
}
