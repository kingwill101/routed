import 'dart:io';

import 'package:routed_security/routed_security.dart' as security;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/router/types.dart';

bool applyCorsHeaders(
  HttpHeaders requestHeaders,
  String _,
  HttpHeaders responseHeaders,
  CorsConfig config,
) {
  return security.applyCorsHeaders(
    requestHeaders,
    responseHeaders,
    security.CorsPolicy(
      enabled: config.enabled,
      allowedOrigins: config.allowedOrigins,
      allowedMethods: config.allowedMethods,
      allowedHeaders: config.allowedHeaders,
      allowCredentials: config.allowCredentials,
      maxAge: config.maxAge,
      exposedHeaders: config.exposedHeaders,
    ),
  );
}

Middleware corsMiddleware() {
  return (EngineContext ctx, Next next) async {
    final config = ctx.engineConfig.security.cors;

    if (!config.enabled) {
      return next();
    }

    final requestHeaders = ctx.request.headers;
    final requestMethod = ctx.request.method;
    final responseHeaders = ctx.response.headers;

    final allowed = applyCorsHeaders(
      requestHeaders,
      requestMethod,
      responseHeaders,
      config,
    );

    if (!allowed) {
      return ctx.string(
        'CORS origin check failed.',
        statusCode: HttpStatus.forbidden,
      );
    }

    if (requestMethod == 'OPTIONS') {
      return ctx.string('', statusCode: HttpStatus.noContent);
    }

    return next();
  };
}
