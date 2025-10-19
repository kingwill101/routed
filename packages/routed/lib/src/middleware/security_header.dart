import 'package:routed/src/context/context.dart';

import 'package:routed/middlewares.dart' show Middleware, Next;

Middleware securityHeadersMiddleware() {
  return (EngineContext ctx, Next next) async {
    final config = ctx.engineConfig;
    if (!config.features.enableSecurityFeatures) {
      return await next();
    }
    if (config.security.csp != null) {
      ctx.response.headers.set('Content-Security-Policy', config.security.csp!);
    }
    if (config.security.xContentTypeOptionsNoSniff) {
      ctx.response.headers.set('X-Content-Type-Options', 'nosniff');
    }
    if (config.security.hstsMaxAge != null) {
      ctx.response.headers.set(
        'Strict-Transport-Security',
        'max-age=${config.security.hstsMaxAge}; includeSubDomains; preload',
      );
    }
    if (config.security.xFrameOptions != null) {
      ctx.response.headers.set(
        'X-Frame-Options',
        config.security.xFrameOptions!,
      );
    }
    return await next();
  };
}
