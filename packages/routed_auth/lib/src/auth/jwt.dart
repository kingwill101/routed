import 'package:http/http.dart' as http;
import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthJwtVerifiedCallback,
        JwtAuthException,
        JwtOptions,
        JwtVerifier,
        buildBearerAuthenticateHeader,
        sanitizeAuthErrorCode,
        verifyJwtBearerAuthorizationAndWriteAttributes;

/// Creates a JWT authentication [Middleware] with the given [options].
///
/// Disabled options pass through to `next`. Enabled middleware reads the
/// configured header and bearer prefix, verifies the token, and writes its
/// claims, subject, header, and authentication attributes to the request
/// before invoking [onVerified] and then `next`. [httpClient] is used for
/// remote key material.
/// A [JwtAuthException] becomes a generic 401 response with a sanitized
/// `WWW-Authenticate` bearer challenge rather than escaping the middleware.
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
///
/// Disabled verifier options pass through to `next`. Otherwise the verifier's
/// [JwtOptions.header] and bearer prefix control extraction; successful claims,
/// subject, header, and authentication attributes are written to the request
/// before [onVerified] and `next` run. Verification
/// failures are converted to a generic 401 response with a sanitized bearer
/// challenge. Reusing [verifier] preserves its configured key and cache
/// lifecycle for the middleware's lifetime.
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
      errorDescription: sanitizeAuthErrorCode(
        reason,
        fallback: 'invalid_token',
      ),
    ),
  );
  if (!ctx.response.isClosed) {
    ctx.errorResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Unauthorized',
    );
  }
}
