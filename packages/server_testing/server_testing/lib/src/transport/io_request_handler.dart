import 'dart:async';
import 'dart:io';

import 'package:server_testing/src/transport/request_handler.dart';

/// A simple [RequestHandler] implementation that adapts a plain
/// `dart:io` request-handling callback to the `server_testing` ecosystem.
///
/// This is intended as the "default" handler for applications that already
/// use `HttpServer` directly and therefore expose a function of the form:
///
/// ```dart
/// FutureOr<void> onRequest(HttpRequest request) async { … }
/// ```
///
/// Instead of re-writing your application to conform to `RequestHandler`,
/// you can simply wrap the existing callback:
///
/// ```dart
/// final handler = IoRequestHandler(onRequest);
///
/// serverTest('GET /ping returns pong', (client) async {
///   final response = await client.get('/ping');
///   response.assertStatus(200).assertBodyEquals('pong');
/// }, handler: handler);
/// ```
///
/// The handler works in both transport modes provided by `server_testing`:
///
///  • `TransportMode.inMemory` – the callback is executed directly with the
///    mock `HttpRequest`.
///  • `TransportMode.ephemeralServer` – an `HttpServer` is started on an
///    ephemeral port and all traffic is forwarded to the callback.
class IoRequestHandler implements RequestHandler {
  /// The user-supplied request handling callback.
  final FutureOr<void> Function(HttpRequest) _onRequest;

  /// The underlying `HttpServer` instance if one has been started
  /// by [startServer]. It is `null` in in-memory mode.
  HttpServer? _server;

  /// Creates a new [IoRequestHandler] that delegates all work to [onRequest].
  ///
  /// The [onRequest] callback is invoked for every incoming [HttpRequest]
  /// whether it originates from the in-memory transport or a real socket.
  IoRequestHandler(FutureOr<void> Function(HttpRequest) onRequest)
    : _onRequest = onRequest;

  @override
  Future<void> handleRequest(HttpRequest request) async {
    // Simply forward the request to the supplied callback.
    await _onRequest(request);
  }

  @override
  Future<int> startServer({int port = 0}) async {
    // Bind to loopback so the test client cannot be accessed externally.
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );

    // Forward all requests to the callback.  Any asynchronous errors are
    // surfaced on stderr to aid debugging.
    _server!.listen((req) {
      try {
        final result = _onRequest(req);
        if (result is Future) {
          result.catchError((Object e, StackTrace st) {
            stderr.writeln('IoRequestHandler error: $e\n$st');
          });
        }
      } on Object catch (e, st) {
        stderr.writeln('IoRequestHandler error: $e\n$st');
        // Ensure the response is closed to avoid hanging sockets.
        _safeClose(req.response);
      }
    });

    return _server!.port;
  }

  @override
  Future<void> close([bool force = true]) async {
    await _server?.close(force: force);
    _server = null;
  }

  /// Attempts to close [response] while swallowing any further exceptions.
  void _safeClose(HttpResponse response) {
    try {
      // Attempt to set a 500 status code; ignore if the response has already
      // been committed.
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Headers already sent, can't set status
      }
      response.close();
    } catch (_) {
      // Ignore secondary errors during shutdown.
    }
  }
}
