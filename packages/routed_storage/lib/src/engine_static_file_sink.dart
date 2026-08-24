import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:server_storage/server_storage.dart';

/// Adapts [EngineContext] to the portable [StaticFileSink] surface.
final class EngineContextStaticFileSink implements StaticFileSink {
  /// Creates a sink that writes static-file output through [ctx].
  EngineContextStaticFileSink(this.ctx);

  /// Request context receiving the static-file response.
  final EngineContext ctx;

  /// HTTP method for the current request.
  @override
  String get method => ctx.method;

  /// Mutable response headers for the current request.
  @override
  HttpHeaders get headers => ctx.headers;

  /// Sets the response status code.
  @override
  set statusCode(int value) {
    ctx.response.statusCode = value;
  }

  /// Sets one response header on the current context.
  @override
  void setHeader(String name, String value) => ctx.setHeader(name, value);

  /// Writes text to the response body.
  @override
  void write(String data) => ctx.response.write(data);

  /// Streams bytes into the response body.
  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      ctx.response.addStream(stream);

  /// Closes the current response.
  @override
  Future<void> close() => ctx.close();

  /// Ends the response with [statusCode] and an optional [message].
  @override
  void abortWithStatus(int statusCode, [String message = '']) =>
      ctx.abortWithStatus(statusCode, message);

  /// Aborts the current response without selecting a status code.
  @override
  void abort() => ctx.abort();
}

/// Convenience so Routed code can pass [EngineContext] directly.
extension FileHandlerEngineContext on FileHandler {
  /// Serves [file] through a Routed request context.
  Future<void> serveToContext(EngineContext ctx, String file) =>
      serveFile(EngineContextStaticFileSink(ctx), file);
}
