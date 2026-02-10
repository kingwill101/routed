// Error Responses Example
//
// Demonstrates how the routed framework automatically negotiates the error
// response format based on the client's `Accept` header:
//
//   - JSON  — for API clients (Accept: application/json, XHR, or JSON body)
//   - HTML  — for browsers (Accept: text/html)
//   - Plain text — fallback when neither is specified
//
// Run the server:
//   dart run bin/server.dart
//
// Then run the client to see the different responses:
//   dart run bin/client.dart
//
// You can also test manually with curl:
//   curl -H "Accept: application/json" http://localhost:3000/not-found
//   curl -H "Accept: text/html"        http://localhost:3000/not-found
//   curl                                http://localhost:3000/not-found
import 'package:routed/routed.dart';
import 'package:routed/middleware.dart';

// ---------------------------------------------------------------------------
// Custom error type — extend EngineError for domain-specific errors.
// Any EngineError with a `code` is content-negotiated automatically.
// ---------------------------------------------------------------------------
class PaymentRequiredError extends EngineError {
  @override
  int? get code => HttpStatus.paymentRequired;

  PaymentRequiredError()
    : super(message: 'A paid subscription is required for this feature');
}

void main() async {
  final engine = Engine();

  // =======================================================================
  // BUILT-IN ERROR TYPES — the framework provides typed errors for common
  // HTTP statuses. All are content-negotiated automatically.
  // =======================================================================

  // -----------------------------------------------------------------------
  // 1. ValidationError (422)
  //    Framework serialises the error map for JSON clients, or renders
  //    an HTML error page for browsers.
  // -----------------------------------------------------------------------
  engine.post('/register', (ctx) async {
    final body = await ctx.body();
    final errors = <String, List<String>>{};

    if (!body.contains('"email"')) {
      errors['email'] = ['Email is required'];
    }
    if (!body.contains('"password"')) {
      errors['password'] = ['Password is required'];
    }

    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }

    return ctx.json({'message': 'User registered'});
  });

  // -----------------------------------------------------------------------
  // 2. ConflictError (409)
  //    Built-in EngineError subclass for resource conflicts.
  // -----------------------------------------------------------------------
  engine.post('/resources', (ctx) {
    throw ConflictError(message: 'Resource already exists');
  });

  // -----------------------------------------------------------------------
  // 3. ForbiddenError (403)
  //    Built-in EngineError subclass for authorization failures.
  // -----------------------------------------------------------------------
  engine.get('/forbidden', (ctx) {
    throw ForbiddenError(
      message: 'You do not have permission to access this resource',
    );
  });

  // -----------------------------------------------------------------------
  // 4. NotFoundError (404)
  //    Built-in EngineError subclass for missing resources.
  // -----------------------------------------------------------------------
  engine.get('/users/{id}', (ctx) {
    throw NotFoundError(message: 'User ${ctx.param('id')} not found');
  });

  // -----------------------------------------------------------------------
  // 5. BadRequestError (400)
  //    Built-in EngineError subclass for malformed requests.
  // -----------------------------------------------------------------------
  engine.post('/parse', (ctx) {
    throw BadRequestError();
  });

  // -----------------------------------------------------------------------
  // 6. Custom EngineError subclass (402 Payment Required)
  //    Shows how to create your own typed error for status codes not
  //    covered by the built-in set.
  // -----------------------------------------------------------------------
  engine.get('/premium', (ctx) {
    throw PaymentRequiredError();
  });

  // =======================================================================
  // RECOVERY MIDDLEWARE — catches unhandled (non-EngineError) exceptions
  // and produces a content-negotiated 500 page. Applied to a specific
  // group so it doesn't swallow the typed errors above.
  // =======================================================================

  // -----------------------------------------------------------------------
  // 7. Unhandled exception (500)
  //    The recovery middleware catches this and produces a content-negotiated
  //    "Internal Server Error" response.
  // -----------------------------------------------------------------------
  engine.group(
    path: '/danger',
    middlewares: [recoveryMiddleware()],
    builder: (router) {
      router.get('/crash', (ctx) {
        throw StateError('Something broke internally');
      });
    },
  );

  // =======================================================================
  // MANUAL errorResponse() — call it directly in your handlers to produce
  // a content-negotiated error without throwing.
  // =======================================================================

  // -----------------------------------------------------------------------
  // 8. Manual errorResponse() — 404 for a missing resource
  // -----------------------------------------------------------------------
  engine.get('/items/{id}', (ctx) {
    final id = ctx.param('id');
    // Pretend lookup failed
    return ctx.errorResponse(
      statusCode: HttpStatus.notFound,
      message: 'Item $id not found',
    );
  });

  // -----------------------------------------------------------------------
  // 9. Manual errorResponse() with a custom JSON body
  //    You can override the default JSON structure when needed.
  // -----------------------------------------------------------------------
  engine.delete('/items/{id}', (ctx) {
    final id = ctx.param('id');
    return ctx.errorResponse(
      statusCode: HttpStatus.gone,
      message: 'Item $id has been permanently deleted',
      jsonBody: {
        'error': 'resource_gone',
        'item_id': id,
        'message': 'Item $id has been permanently deleted',
      },
    );
  });

  // =======================================================================
  // NEGOTIATION HELPERS — inspect wantsJson / acceptsHtml / accepts()
  // =======================================================================

  // -----------------------------------------------------------------------
  // 10. Shows what the negotiation helpers return for the current request
  // -----------------------------------------------------------------------
  engine.get('/inspect', (ctx) {
    return ctx.json({
      'wantsJson': ctx.wantsJson,
      'acceptsHtml': ctx.acceptsHtml,
      'acceptsXml': ctx.accepts('application/xml'),
    });
  });

  // -----------------------------------------------------------------------
  // 11. A route that doesn't exist (404)
  //    Try: curl -H "Accept: text/html" http://localhost:3000/no-such-route
  //    The framework's built-in 404 handler is also content-negotiated.
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // A healthy route for comparison
  // -----------------------------------------------------------------------
  engine.get('/health', (ctx) => ctx.json({'status': 'ok'}));

  await engine.serve(port: 3000, echo: true);
  print('Error responses example running at http://localhost:3000');
  print('Run "dart run bin/client.dart" to see content negotiation in action');
}
