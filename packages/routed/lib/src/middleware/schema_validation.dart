import 'package:routed/src/context/context.dart';
import 'package:routed/src/openapi/schema.dart';
import 'package:routed/src/router/types.dart';

/// Creates a middleware that automatically validates incoming request data
/// against a [RouteSchema]'s validation rules.
///
/// This middleware inspects the route's [RouteSchema.validationRules] and, if
/// present, validates the request body/query parameters using the framework's
/// existing validation pipeline (which selects the appropriate binding — JSON,
/// form, query — based on the HTTP method and content type).
///
/// On validation failure, a [ValidationError] is thrown and caught by the
/// engine's global error handler, which returns a 422 Unprocessable Entity
/// response with detailed field-level error messages.
///
/// This middleware is intended to be injected automatically by [EngineRoute]
/// when a route has a schema with validation rules. It runs just before the
/// route handler in the middleware chain.
///
/// Example:
/// ```dart
/// engine.post('/users', createUser, schema: RouteSchema.fromRules({
///   'name': 'required|string|min:2',
///   'email': 'required|email',
/// }));
/// ```
Middleware schemaValidationMiddleware(RouteSchema schema) {
  final rules = schema.validationRules;

  return (EngineContext ctx, Next next) async {
    if (rules != null && rules.isNotEmpty) {
      // ctx.validate() delegates to the appropriate binding (JSON, form,
      // query) based on the HTTP method and content type. It throws
      // ValidationError on failure, which the engine's global error handler
      // converts to a 422 response.
      await ctx.validate(rules);
    }
    return next();
  };
}
