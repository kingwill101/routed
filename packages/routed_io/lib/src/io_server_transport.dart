import 'dart:async';
import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'package:routed_io/src/io_http_connection.dart';
import 'package:routed_io/src/io_portable.dart';

/// [ServerTransport] using `dart:io` [HttpServer].
///
/// Default path uses the native [HttpRequest] fast path
/// ([Engine.handleConnection] + [NativeRequestHandle]) so websockets and
/// progressive response writes keep working.
///
/// Set [portableEdge] to route each request through
/// [dispatchIoExchange] / [Engine.handlePortable] (value-style; buffers the
/// response). Useful for testing parity with Node/Workers hosts.
final class IoServerTransport implements ServerTransport {
  /// Creates a `dart:io` server transport.
  ///
  /// Set [portableEdge] to use the portable request/response path. Set
  /// [shared] to allow the bound socket to be shared between processes.
  const IoServerTransport({
    this.shared = true,
    this.echo = false,
    this.portableEdge = false,
  });

  /// Whether the bound socket may be shared between processes.
  final bool shared;

  /// Whether to print the bound address after the server starts.
  final bool echo;

  /// When true, each request uses [dispatchIoExchange] instead of the native
  /// [HttpRequest] pipeline.
  final bool portableEdge;

  @override
  Future<ServerHandle> serve(Engine engine, ServerOptions options) async {
    if (engine.isClosed) {
      throw StateError('Cannot serve on a closed engine');
    }

    // Ensure routes / providers ready
    await engine.initialize();

    final server = await HttpServer.bind(
      options.host,
      options.port,
      shared: options.shared || shared,
    );

    if (echo) {
      // The optional echo flag intentionally writes a startup hint for CLI
      // users.
      // ignore: avoid_print
      print('Engine listening on http://${options.host}:${server.port}');
    }

    // The subscription is transferred to the returned handle and canceled by
    // [_IoServerHandle.close].
    // ignore: cancel_subscriptions
    final sub = server.listen((HttpRequest httpRequest) {
      final work = portableEdge
          ? dispatchIoExchange(engine, httpRequest)
          : engine.handleConnection(
              IoHttpConnection(httpRequest).connection,
            );

      // Concurrent requests; errors closed best-effort on the socket.
      unawaited(
        work.catchError((Object e, StackTrace s) async {
          try {
            httpRequest.response.statusCode = HttpStatus.internalServerError;
            await httpRequest.response.close();
          } on Object catch (_) {}
        }),
      );
    });

    return _IoServerHandle(server, sub);
  }
}

final class _IoServerHandle implements ServerHandle {
  _IoServerHandle(this._server, this._subscription);

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;

  @override
  String get host => _server.address.host;

  @override
  int get port => _server.port;

  @override
  Future<void> close({bool force = false}) async {
    await _subscription.cancel();
    await _server.close(force: force);
  }
}
