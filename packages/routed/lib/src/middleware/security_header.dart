import 'package:routed/src/context/context.dart';

import '../../middlewares.dart';

Middleware securityHeadersMiddleware() {
  return (EngineContext ctx) async {
    final config = ctx.engineConfig;
    if (!config.features.enableSecurityFeatures) {
      await ctx.next();
      return;
    }
    if (config.security.csp != null) {
      ctx.response.headers.add('Content-Security-Policy', config.security.csp!);
    }
    if (config.security.xContentTypeOptionsNoSniff) {
      ctx.response.headers.add('X-Content-Type-Options', 'nosniff');
    }
    if (config.security.hstsMaxAge != null) {
      ctx.response.headers.add('Strict-Transport-Security',
          'max-age=${config.security.hstsMaxAge}; includeSubDomains; preload');
    }
    if (config.security.xFrameOptions != null) {
      ctx.response.headers
          .add('X-Frame-Options', config.security.xFrameOptions!);
    }
    await ctx.next();
  };
}
