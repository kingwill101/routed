import 'dart:async';

import 'package:routed/src/context/context.dart';

/// A handler function signature that takes an [EngineContext] as a parameter.
/// This function allows you to modify the request or response, or perform other
/// logic. After performing the necessary operations, you can optionally call
/// [ctx.next()] to proceed to the next handler in the chain. If [ctx.next()] is
/// not called, the chain will stop at this handler.
typedef Handler = FutureOr<void> Function(EngineContext ctx);

/// A middleware function signature that takes an [EngineContext] as a parameter.
/// Similar to a handler, this function allows you to modify the request or response,
/// or perform other logic. You can optionally call [ctx.next()] to proceed to the
/// next middleware in the chain. If [ctx.next()] is not called, the chain will stop
/// at this middleware.
typedef Middleware = FutureOr<void> Function(EngineContext ctx);
