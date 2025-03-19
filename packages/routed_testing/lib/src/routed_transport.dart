import 'dart:io';

import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

/// Adapter for the Routed Engine that conforms to the RequestHandler interface.
class RoutedRequestHandler implements RequestHandler {
  /// The Engine instance
  final Engine _engine;
  HttpServer? _server;

  /// Creates a new handler from an Engine instance
  RoutedRequestHandler([Engine? engine]) : _engine = engine ?? Engine();

  @override
  Future<void> handleRequest(HttpRequest request) async {
    await beforeRequest();
    return _engine.handleRequest(request);
  }

  beforeRequest() async {
    // Ensure proxy configuration is parsed
    if (_engine.config.features.enableProxySupport) {
      await _engine.config.parseTrustedProxies();
    }
  }

  @override
  Future<int> startServer({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

    // Set up request handling
    _server!.listen((request) {
      _engine.handleRequest(request);
    });

    return _server!.port;
  }

  @override
  Future<void> close([bool force = true]) async {
    await _server?.close(force: force);
    _server = null;
  }
}
