import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show
        AuthOAuthValidatedCallback,
        OAuthBearerValidationResult,
        OAuth2Exception,
        OAuth2TokenIntrospector,
        OAuthIntrospectionOptions,
        validateOAuthBearerAuthorization,
        oauthClaimsAttribute,
        oauthScopeAttribute,
        oauthTokenAttribute;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

/// Creates a middleware for OAuth2 token introspection.
///
/// This middleware validates incoming OAuth2 tokens using the provided
/// [options]. If the token is valid, its claims and attributes are added
/// to the request context.
///
/// - [options]: Configuration options for the introspection.
/// - [onValidated]: Optional callback invoked after successful validation.
/// - [httpClient]: Optional HTTP client for making introspection requests.
///
/// Returns a middleware function that can be used in the routing pipeline.
///
/// Example:
/// ```dart
/// final middleware = oauth2Introspection(
///   OAuthIntrospectionOptions(
///     endpoint: Uri.parse('https://example.com/introspect'),
///     clientId: 'my-client-id',
///     clientSecret: 'my-client-secret',
///   ),
/// );
/// ```
Middleware oauth2Introspection(
  OAuthIntrospectionOptions options, {
  AuthOAuthValidatedCallback<EngineContext>? onValidated,
  http.Client? httpClient,
}) {
  final introspector = OAuth2TokenIntrospector(options, httpClient: httpClient);

  return (EngineContext ctx, Next next) async {
    OAuthBearerValidationResult validation;
    try {
      validation = await validateOAuthBearerAuthorization(
        authorizationHeader: ctx.request.header(
          HttpHeaders.authorizationHeader,
        ),
        introspector: introspector,
      );
    } on OAuth2Exception catch (error) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write(error.message);
      return ctx.response;
    }
    final token = validation.token;
    final result = validation.result;

    ctx.request
      ..setAttribute(oauthTokenAttribute, token)
      ..setAttribute(oauthClaimsAttribute, result.raw)
      ..setAttribute(oauthScopeAttribute, result.scope);

    if (onValidated != null) {
      await onValidated(result, ctx);
    }

    return await next();
  };
}
