import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show
        OAuth2Exception,
        OAuth2TokenIntrospector,
        OAuthIntrospectionOptions,
        OAuthIntrospectionResult;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

/// Attribute key for storing the OAuth2 access token in the request context.
const String oauthTokenAttribute = 'auth.oauth.access_token';

/// Attribute key for storing OAuth2 claims in the request context.
const String oauthClaimsAttribute = 'auth.oauth.claims';

/// Attribute key for storing OAuth2 scopes in the request context.
const String oauthScopeAttribute = 'auth.oauth.scope';

typedef OAuthOnValidated =
    FutureOr<void> Function(
      OAuthIntrospectionResult result,
      EngineContext context,
    );

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
  OAuthOnValidated? onValidated,
  http.Client? httpClient,
}) {
  final introspector = OAuth2TokenIntrospector(options, httpClient: httpClient);

  return (EngineContext ctx, Next next) async {
    final header = ctx.request.header('Authorization');
    if (header.isEmpty || !header.startsWith('Bearer ')) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('missing token');
      return ctx.response;
    }
    final token = header.substring('Bearer '.length).trim();
    if (token.isEmpty) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('missing token');
      return ctx.response;
    }

    OAuthIntrospectionResult result;
    try {
      result = await introspector.validate(token);
    } on OAuth2Exception catch (error) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write(error.message);
      return ctx.response;
    }

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
