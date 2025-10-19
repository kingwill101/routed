import 'dart:io';

import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

/// Adapter for the Routed Engine that conforms to the RequestHandler interface.
///
/// This class allows you to use `server_testing` with the Routed framework by
/// implementing the [RequestHandler] interface. It delegates all HTTP request
/// handling to a Routed [Engine] instance.
///
/// ## Example
///
/// ```dart
/// import 'package:routed/routed.dart';
/// import 'package:routed_testing/routed_testing.dart';
/// import 'package:server_testing/server_testing.dart';
///
/// void main() {
///   // Create a Routed engine with your routes
///   final engine = Engine()
///     ..get('/users', (req, res) {
///       return res.json({
///         'users': [{'name': 'Alice'}, {'name': 'Bob'}]
///       });
///     });
///
///   // Wrap it in a RoutedRequestHandler
///   final handler = RoutedRequestHandler(engine);
///
///   // Use it with server_testing
///   engineTest('GET /users returns list of users', (client) async {
///     final response = await client.get('/users');
///
///     response
///       .assertStatus(200)
///       .assertJson((json) {
///         json.has('users').count('users', 2);
///       });
///   }, handler: handler);
/// }
/// ```
class RoutedRequestHandler implements RequestHandler {
  /// The Routed Engine instance that will handle the requests.
  ///
  /// This engine contains all your route definitions and middleware.
  /// If not provided in the constructor, a new empty Engine is created.
  final Engine _engine;

  /// The HTTP server instance when using [TransportMode.ephemeralServer].
  HttpServer? _server;

  final bool autoCloseEngine;

  /// Creates a new handler that adapts a Routed Engine to the RequestHandler interface.
  ///
  /// [engine] is an optional Routed Engine instance. If not provided, a new
  /// empty Engine will be created.
  ///
  /// Example:
  /// ```dart
  /// // Use an existing engine
  /// final engine = Engine()..get('/hello', (req, res) => res.send('Hello'));
  /// final handler = RoutedRequestHandler(engine);
  ///
  /// // Or create a handler with a new engine
  /// final handler = RoutedRequestHandler();
  /// ```
  RoutedRequestHandler([Engine? engine, this.autoCloseEngine = false])
    : _engine = engine ?? Engine();

  /// Handles an HTTP request by delegating to the Routed Engine.
  ///
  /// This method first runs preliminary setup through [beforeRequest],
  /// then delegates to the Engine's request handling logic.
  @override
  Future<void> handleRequest(HttpRequest request) async {
    await beforeRequest();
    return _engine.handleRequest(request);
  }

  /// Performs pre-request setup operations.
  ///
  /// Currently, this ensures proxy configuration is properly parsed if
  /// proxy support is enabled in the engine configuration.
  Future<void> beforeRequest() async {
    // Wait for engine boot to complete before handling requests
    // Ensure proxy configuration is parsed
    if (_engine.config.features.enableProxySupport) {
      await _engine.config.parseTrustedProxies();
    }
  }

  /// Starts an HTTP server on the specified port.
  ///
  /// This method is called by server_testing when using the
  /// [TransportMode.ephemeralServer] mode. It binds an HTTP server to the
  /// given port and configures it to use the Engine for request handling.
  ///
  /// [port] is the port to bind to (0 for random port)
  /// Returns the actual port number that the server is bound to.
  @override
  Future<int> startServer({int port = 0}) async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );

    // Set up request handling
    _server!.listen((request) {
      _engine.handleRequest(request);
    });
    _engine.attachServer(_server!);

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
    if (autoCloseEngine) {
      await _engine.close();
    }
  }
}
