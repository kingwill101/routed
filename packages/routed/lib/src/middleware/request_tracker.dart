import 'package:routed/routed.dart';

/// Middleware function to track the duration of each request.
///
/// This middleware captures the start time of the request, allows the request
/// to proceed, and then calculates the duration of the request once it completes.
/// The duration and completion time are stored in the context data for further use.
Middleware requestTrackerMiddleware() {
  return (EngineContext ctx) async {
    // Capture the start time of the request.
    final startTime = DateTime.now();

    try {
      // Proceed with the next middleware or request handler.
      await ctx.next();
    } finally {
      // Calculate the duration of the request by finding the difference
      // between the current time and the start time.
      final duration = DateTime.now().difference(startTime);

      // Store the request duration in the context data.
      ctx.setContextData('request_duration', duration);

      // Store the request completion time in the context data.
      ctx.setContextData('request_completed', DateTime.now());
    }
  };
}
