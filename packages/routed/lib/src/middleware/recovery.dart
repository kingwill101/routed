import 'dart:io';
import 'package:stack_trace/stack_trace.dart';
import '../context/context.dart';
import '../router/types.dart';

/// A type definition for the recovery handler function.
/// This function is called when an error occurs during the execution of a middleware.
typedef RecoveryHandler = void Function(
    EngineContext ctx, Object error, StackTrace stack);

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
  // Use the default recovery handler if none is provided.
  handler ??= _defaultRecoveryHandler;

  return (EngineContext ctx) async {
    try {
      // Proceed to the next middleware in the chain.
      await ctx.next();
    } catch (error, stackTrace) {
      // Determine if the error is related to a broken pipe or connection reset.
      final isBrokenPipe = _isBrokenPipeError(error);

      if (!isBrokenPipe) {
        // Log the error and stack trace if it is not a broken pipe error.
        final trace = Trace.from(stackTrace).terse;
        print('[Recovery] ${DateTime.now()}: $error\n$trace');

        // Call the custom recovery handler.
        handler!(ctx, error, stackTrace);
      } else {
        // Quietly abort the context for broken pipe errors.
        ctx.abort();
      }
    }
  };
}

/// The default recovery handler function.
///
/// This function sends a JSON response with a 500 Internal Server Error status code
/// if the context is not already closed.
void _defaultRecoveryHandler(
    EngineContext ctx, Object error, StackTrace stack) {
  if (!ctx.isClosed) {
    ctx.json(
      {'error': 'Internal Server Error'},
      statusCode: HttpStatus.internalServerError,
    );
  }
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
