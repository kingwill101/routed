import 'dart:async';
import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'io_http_connection.dart';

/// [ServerTransport] using `dart:io` [HttpServer].
final class IoServerTransport implements ServerTransport {
  const IoServerTransport({
    this.shared = true,
    this.echo = false,
  });

  final bool shared;
  final bool echo;

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
      final conn = IoHttpConnection(httpRequest);
      // Concurrent requests; errors closed best-effort on the socket.
      unawaited(
        engine.handleConnection(conn.connection).catchError((Object e, StackTrace s) async {
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
