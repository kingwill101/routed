import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';
import 'package:server_auth/server_auth.dart'
    show
        JwtAuthException,
        AuthJwtVerifiedCallback,
        buildBearerAuthenticateHeader,
        JwtOptions,
        JwtVerifier,
        verifyJwtBearerAuthorizationAndWriteAttributes;

/// Creates a JWT authentication [Middleware] with the given [options].
Middleware jwtAuthentication(
  JwtOptions options, {
  AuthJwtVerifiedCallback<EngineContext>? onVerified,
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
  AuthJwtVerifiedCallback<EngineContext>? onVerified,
}) {
  final options = verifier.options;

  return (EngineContext ctx, Next next) async {
    if (!options.enabled) {
      return next();
    }

    final headerValue = ctx.request.header(options.header);
    try {
      await verifyJwtBearerAuthorizationAndWriteAttributes(
        authorizationHeader: headerValue,
        verifier: verifier,
        setAttribute: ctx.request.setAttribute,
        context: ctx,
        onVerified: onVerified,
      );

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
    buildBearerAuthenticateHeader(
      error: 'invalid_token',
      errorDescription: reason,
    ),
  );
  if (!ctx.response.isClosed) {
    ctx.errorResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Unauthorized',
    );
  }
}
