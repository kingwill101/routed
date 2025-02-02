import 'dart:async';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

/// Middleware that enforces a timeout on the request processing chain.
///
/// If the chain takes longer than the specified [duration], the middleware
/// will close the response with a 504 Gateway Timeout status code.
///
/// [duration] specifies the maximum amount of time the request is allowed
/// to be processed before timing out.
Middleware timeoutMiddleware(Duration duration) {
  return (ctx) async {
    // Print a debug message indicating the middleware has been invoked.
    print("Timeout middleware invoked with duration: $duration");

    // Start a timer that will trigger after the specified [duration].
    final timer = Timer(duration, () {
      // Check if the response context is still open.
      // If it is, close the response with a 504 Gateway Timeout status code.
      if (!ctx.isClosed) {
        ctx.string(statusCode: 504, 'Gateway Timeout');
      }
    });

    try {
      // Proceed to the next middleware or handler in the chain.
      await ctx.next();
    } finally {
      // Cancel the timer once the request processing is complete,
      // regardless of whether it completed successfully or with an exception.
      timer.cancel();
    }
  };
}
