import 'package:routed/src/context/context.dart';
import 'package:routed_security/routed_security.dart' as security;

import 'package:routed/middlewares.dart' show Middleware, Next;

Middleware securityHeadersMiddleware() {
  return (EngineContext ctx, Next next) async {
    final config = ctx.engineConfig;
    if (!config.features.enableSecurityFeatures) {
      return await next();
    }

    final headers = security.buildSecurityHeaders(
      security.SecurityHeaderPolicy(
        csp: config.security.csp,
        xContentTypeOptionsNoSniff: config.security.xContentTypeOptionsNoSniff,
        hstsMaxAge: config.security.hstsMaxAge,
        xFrameOptions: config.security.xFrameOptions,
      ),
    );

    headers.forEach((name, value) {
      ctx.response.headers.set(name, value);
    });

    return await next();
  };
}
