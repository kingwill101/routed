import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

Middleware requestSizeLimitMiddleware() {
  return (EngineContext ctx, Next next) async {
    return await next();
  };
}
