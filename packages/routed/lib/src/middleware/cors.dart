import 'dart:io';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

Middleware corsMiddleware() {
  return (EngineContext ctx) async {
    final config = ctx.engineConfig.security.cors;

    if (!config.enabled) {
      await ctx.next();
      return;
    }

    final request = ctx.request.httpRequest;
    final response = ctx.response;

    // Origin check.
    String origin = request.headers.value('Origin') ?? '*';
    if (config.allowedOrigins.contains('*')) {
      response.headers.add('Access-Control-Allow-Origin', '*');
    } else if (config.allowedOrigins.contains(origin)) {
      response.headers.add('Access-Control-Allow-Origin', origin);
      // Set Vary: Origin to indicate that the response varies based on the Origin header.
      response.headers.add('Vary', 'Origin');
    } else {
      ctx.abortWithStatus(HttpStatus.forbidden, 'CORS origin check failed.');
      return;
    }

    // Credentials.
    if (config.allowCredentials) {
      response.headers.add('Access-Control-Allow-Credentials', 'true');
    }

    // Method.
    response.headers
        .add('Access-Control-Allow-Methods', config.allowedMethods.join(', '));

    // Headers.
    if (config.allowedHeaders.isNotEmpty) {
      response.headers.add(
          'Access-Control-Allow-Headers', config.allowedHeaders.join(', '));
    }

    // Exposed headers.
    if (config.exposedHeaders != null) {
      response.headers
          .add('Access-Control-Expose-Headers', config.exposedHeaders!);
    }

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      ctx.abortWithStatus(HttpStatus.noContent);
      return;
    }

    await ctx.next();
  };
}
