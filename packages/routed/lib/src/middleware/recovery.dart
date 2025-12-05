import 'dart:io';
import 'package:stack_trace/stack_trace.dart';
import '../context/context.dart';
import '../router/types.dart';

/// A type definition for the recovery handler function.
/// This function is called when an error occurs during the execution of a middleware.
typedef RecoveryHandler =
    void Function(EngineContext ctx, Object error, StackTrace stack);

const String _recoveryHandledKey = '__recoveryHandled';

/// Middleware that provides error recovery functionality.
///
/// This middleware catches any errors that occur during the execution of the next middleware
/// in the chain. If an error occurs, it checks if the error is related to a broken pipe or
/// connection reset. If it is not, it logs the error and stack trace, and then calls the
/// provided recovery handler. If no custom handler is provided, a default handler is used.
///
/// If the error is related to a broken pipe or connection reset, the middleware quietly aborts
/// the context without logging or calling the handler.
Middleware recoveryMiddleware({RecoveryHandler? handler}) {
  handler ??= _defaultRecoveryHandler;

  return (EngineContext ctx, Next next) async {
    try {
      return await next();
    } catch (error, stackTrace) {
      final isBrokenPipe = _isBrokenPipeError(error);

      if (!isBrokenPipe) {
        final trace = Trace.from(stackTrace).terse;
        // print suppressed in tests; could route to logger
        // print('[Recovery] ${DateTime.now()}: $error\n$trace');
        final enrichedStack = StackTrace.fromString(
          'Route: ${ctx.request.uri.path}\n${trace.toString()}',
        );
        handler!(ctx, error, enrichedStack);
        // Send the default JSON response only if the handler hasn't already
        // completed / closed the context.
        final handled = ctx.get<bool>(_recoveryHandledKey) ?? false;
        if (!ctx.isClosed && !handled) {
          ctx.set(_recoveryHandledKey, true);
          return ctx.json({
            'error': 'Internal Server Error',
          }, statusCode: HttpStatus.internalServerError);
        }
        // The response has already been handled inside the custom recovery
        // handler, so we simply return the current response.
        return ctx.response;
      } else {
        ctx.abort();
        return ctx.string('', statusCode: HttpStatus.internalServerError);
      }
    }
  };
}

/// The default recovery handler function.
///
/// This function sends a JSON response with a 500 Internal Server Error status code
/// if the context is not already closed.
void _defaultRecoveryHandler(
  EngineContext ctx,
  Object error,
  StackTrace stack,
) {
  // Default handler intentionally left blank. The middleware will emit
  // the fallback response when the handler does not override it.
}

/// Checks if the given error is related to a broken pipe or connection reset.
///
/// This function examines the error message to determine if it contains phrases
/// indicating a broken pipe or connection reset by peer.
///
/// Returns `true` if the error is related to a broken pipe or connection reset,
/// otherwise returns `false`.
bool _isBrokenPipeError(Object error) {
  if (error is SocketException) {
    final message = error.message.toLowerCase();
    return message.contains('broken pipe') ||
        message.contains('connection reset by peer');
  }
  return false;
}
