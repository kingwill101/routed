import 'package:routed/routed.dart';

/// Middleware function to track the duration of each request.
///
/// This middleware captures the start time of the request, allows the request
/// to proceed, and then calculates the duration of the request once it completes.
/// The duration and completion time are stored in the context data for further use.
Middleware requestTrackerMiddleware() {
  return (EngineContext ctx, Next next) async {
    final startTime = DateTime.now();
    ctx.setContextData('_routed_request_duration', Duration.zero);
    ctx.setContextData('_routed_request_completed', startTime);

    try {
      return await next();
    } finally {
      final duration = DateTime.now().difference(startTime);
      ctx.setContextData('_routed_request_duration', duration);
      ctx.setContextData('_routed_request_completed', DateTime.now());
    }
  };
}
