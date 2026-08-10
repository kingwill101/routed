import 'dart:async';

import 'package:routed/routed.dart';
import 'package:server_storage/server_storage.dart';

/// Adapts [EngineContext] to the portable [StaticFileSink] surface.
final class EngineContextStaticFileSink implements StaticFileSink {
  EngineContextStaticFileSink(this.ctx);

  final EngineContext ctx;

  @override
  String get method => ctx.method;

  @override
  HttpHeaders get headers => ctx.headers;

  @override
  set statusCode(int value) {
    ctx.response.statusCode = value;
  }

  @override
  void setHeader(String name, String value) => ctx.setHeader(name, value);

  @override
  void write(String data) => ctx.response.write(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      ctx.response.addStream(stream);

  @override
  Future<void> close() => ctx.close();

  @override
  void abortWithStatus(int statusCode, [String message = '']) =>
      ctx.abortWithStatus(statusCode, message);

  @override
  void abort() => ctx.abort();
}

/// Convenience so Routed code can pass [EngineContext] directly.
extension FileHandlerEngineContext on FileHandler {
  Future<void> serveToContext(EngineContext ctx, String file) =>
      serveFile(EngineContextStaticFileSink(ctx), file);
}
