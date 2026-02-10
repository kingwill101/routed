import 'dart:async';
import 'dart:io';

import 'package:routed/routed.dart';

/// Middleware that enforces a timeout on the request processing chain.
///
/// If the chain takes longer than the specified [duration], the middleware
/// will close the response with a 504 Gateway Timeout status code.
///
/// [duration] specifies the maximum amount of time the request is allowed
/// to be processed before timing out.
Middleware timeoutMiddleware(Duration duration) {
  return (ctx, next) {
    Response completeWithTimeout() {
      // Prevent further handlers from writing
      ctx.abort();
      if (!ctx.isClosed) {
        // Write timeout directly to the underlying response to avoid hitting
        // higher-level render logic which may ignore writes after abort.
        ctx.response.statusCode = HttpStatus.gatewayTimeout;
        if (ctx.wantsJson) {
          ctx.response.headers.contentType = ContentType.json;
          ctx.response.write('{"error":"Gateway Timeout","status":504}');
        } else if (ctx.acceptsHtml) {
          ctx.response.headers.contentType = ContentType.html;
          ctx.response.write(
            '<!DOCTYPE html><html><head><title>504</title></head>'
            '<body style="font-family:system-ui;display:flex;justify-content:center;'
            'align-items:center;min-height:100vh;margin:0"><div style="text-align:center">'
            '<h1 style="font-size:4rem;font-weight:300;color:#868e96">504</h1>'
            '<p>Gateway Timeout</p></div></body></html>',
          );
        } else {
          ctx.response.write('Gateway Timeout');
        }
        unawaited(ctx.response.close());
      }
      return ctx.response;
    }

    final elapsed = DateTime.now().difference(ctx.request.startedAt);
    final remaining = duration - elapsed;

    if (remaining <= Duration.zero) {
      return Future<Response>.value(completeWithTimeout());
    }

    final completer = Completer<Response>();
    late Timer timer;

    Future<Response>.value(next())
        .then((result) {
          if (!completer.isCompleted) {
            timer.cancel();
            completer.complete(result);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            timer.cancel();
            completer.completeError(error, stackTrace);
          }
        });

    timer = Timer(remaining, () {
      if (!ctx.isClosed && !completer.isCompleted) {
        final response = completeWithTimeout();
        completer.complete(response);
      }
    });

    return completer.future;
  };
}
