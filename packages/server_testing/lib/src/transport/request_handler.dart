import 'dart:io';

/// Defines the interface for handling HTTP requests.
/// This is the core abstraction that different server implementations will adapt to.
abstract class RequestHandler {
  /// Handles an HTTP request directly.
  ///
  /// For in-memory transport, this will be called with mock HttpRequest objects.
  /// For server transport, this will be used to launch a server process.
  ///
  /// [request] is the HTTP request to handle.
  Future<void> handleRequest(HttpRequest request);

  /// Starts a server on the given port (for server-based transports).
  ///
  /// [port] is the port to bind to (0 for random port)
  /// Returns the bound port number.
  Future<int> startServer({int port = 0});

  /// Releases any resources used by this handler.
  Future<void> close([bool force = true]);
}
