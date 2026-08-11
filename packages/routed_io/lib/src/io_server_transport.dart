import 'dart:async';
import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'io_http_connection.dart';
import 'io_portable.dart';

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
  const IoServerTransport({
    this.shared = true,
    this.echo = false,
    this.portableEdge = false,
  });

  final bool shared;
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
      // ignore: avoid_print
      print('Engine listening on http://${options.host}:${server.port}');
    }

    final sub = server.listen((HttpRequest httpRequest) {
      final Future<void> work = portableEdge
          ? dispatchIoExchange(engine, httpRequest)
          : engine.handleConnection(IoHttpConnection(httpRequest).connection);

      // Concurrent requests; errors closed best-effort on the socket.
      unawaited(
        work.catchError((Object e, StackTrace s) async {
          try {
            httpRequest.response.statusCode = HttpStatus.internalServerError;
            await httpRequest.response.close();
          } catch (_) {}
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
