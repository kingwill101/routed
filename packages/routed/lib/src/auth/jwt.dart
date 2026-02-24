import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';
import 'package:server_auth/server_auth.dart'
    show
        JwtAuthException,
        JwtOptions,
        JwtPayload,
        JwtVerifier,
        jwtClaimsAttribute,
        jwtHeadersAttribute,
        jwtSubjectAttribute;

/// Callback invoked after a JWT has been successfully verified.
typedef JwtOnVerified =
    FutureOr<void> Function(JwtPayload payload, EngineContext context);

/// Creates a JWT authentication [Middleware] with the given [options].
Middleware jwtAuthentication(
  JwtOptions options, {
  JwtOnVerified? onVerified,
  http.Client? httpClient,
}) {
  return jwtAuthenticationWithVerifier(
    JwtVerifier(options: options, httpClient: httpClient),
    onVerified: onVerified,
  );
}

/// Creates JWT authentication [Middleware] with an existing [verifier].
Middleware jwtAuthenticationWithVerifier(
  JwtVerifier verifier, {
  JwtOnVerified? onVerified,
}) {
  final options = verifier.options;

  return (EngineContext ctx, Next next) async {
    if (!options.enabled) {
      return next();
    }

    final headerValue = ctx.request.header(options.header);
    final token = _extractToken(headerValue, options.bearerPrefix);
    if (token == null) {
      _writeUnauthorized(ctx, 'missing_token');
      return ctx.response;
    }

    try {
      final payload = await verifier.verifyToken(token);
      ctx.request
        ..setAttribute(jwtClaimsAttribute, payload.claims)
        ..setAttribute(jwtHeadersAttribute, payload.headers)
        ..setAttribute(jwtSubjectAttribute, payload.subject);

      if (onVerified != null) {
        await onVerified(payload, ctx);
      }

      return await next();
    } on JwtAuthException catch (error) {
      _writeUnauthorized(ctx, error.message);
      return ctx.response;
    }
  };
}

void _writeUnauthorized(EngineContext ctx, String reason) {
  ctx.response.headers.set(
    HttpHeaders.wwwAuthenticateHeader,
    'Bearer error="invalid_token", error_description="$reason"',
  );
  if (!ctx.response.isClosed) {
    ctx.errorResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Unauthorized',
    );
  }
}

String? _extractToken(String? headerValue, String prefix) {
  if (headerValue == null || headerValue.isEmpty) {
    return null;
  }
  if (!headerValue.startsWith(prefix)) {
    return null;
  }
  final token = headerValue.substring(prefix.length).trim();
  return token.isEmpty ? null : token;
}
