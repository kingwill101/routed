import 'dart:async';

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
        ctx.response.write('Gateway Timeout');
        ctx.response.close();
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
