import 'dart:async';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';

/// Next function for middleware composition, returns a Response when called.
typedef Next = FutureOr<Response> Function();

/// Route handler: may be sync/async and may return Response or void.
typedef RouteHandler = FutureOr<dynamic> Function(EngineContext ctx);

/// Preferred handler signature for new code.
typedef Handler = FutureOr<Response> Function(EngineContext ctx);

/// Middleware: may short-circuit by returning a Response, or call next().
typedef Middleware = FutureOr<Response> Function(EngineContext ctx, Next next);
