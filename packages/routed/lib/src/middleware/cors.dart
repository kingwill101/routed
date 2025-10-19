import 'dart:io';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/router/types.dart';

bool applyCorsHeaders(
  HttpHeaders requestHeaders,
  String requestMethod,
  HttpHeaders responseHeaders,
  CorsConfig config,
) {
  if (!config.enabled) {
    return true;
  }

  final origin = requestHeaders.value('Origin');
  String? allowOrigin;

  if (config.allowedOrigins.contains('*')) {
    if (config.allowCredentials && origin != null) {
      allowOrigin = origin;
      responseHeaders.add(HttpHeaders.varyHeader, 'Origin');
    } else {
      allowOrigin = '*';
    }
  } else if (origin != null && config.allowedOrigins.contains(origin)) {
    allowOrigin = origin;
    responseHeaders.add(HttpHeaders.varyHeader, 'Origin');
  } else {
    return false;
  }

  responseHeaders.set(HttpHeaders.accessControlAllowOriginHeader, allowOrigin);

  if (config.allowCredentials && allowOrigin != '*') {
    responseHeaders.set(
      HttpHeaders.accessControlAllowCredentialsHeader,
      'true',
    );
  }

  final requestedMethod = requestHeaders.value(
    HttpHeaders.accessControlRequestMethodHeader,
  );

  if (requestedMethod != null &&
      config.allowedMethods.isNotEmpty &&
      !config.allowedMethods.contains(requestedMethod)) {
    return false;
  }

  responseHeaders.set(
    HttpHeaders.accessControlAllowMethodsHeader,
    config.allowedMethods.join(', '),
  );

  final requestedHeaders =
      requestHeaders[HttpHeaders.accessControlRequestHeadersHeader];

  if (config.allowedHeaders.isNotEmpty) {
    responseHeaders.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      config.allowedHeaders.join(', '),
    );
  } else if (requestedHeaders != null && requestedHeaders.isNotEmpty) {
    responseHeaders.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      requestedHeaders.join(', '),
    );
  }

  if (config.maxAge != null) {
    responseHeaders.set(
      HttpHeaders.accessControlMaxAgeHeader,
      config.maxAge!.toString(),
    );
  }

  if (config.exposedHeaders.isNotEmpty) {
    responseHeaders.set(
      'Access-Control-Expose-Headers',
      config.exposedHeaders.join(', '),
    );
  }

  return true;
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
