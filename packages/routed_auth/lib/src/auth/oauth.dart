import 'package:http/http.dart' as http;
import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthOAuthValidatedCallback,
        OAuth2Exception,
        OAuth2TokenIntrospector,
        OAuthIntrospectionOptions,
        validateOAuthBearerAuthorizationAndWriteAttributes;

/// Creates a middleware for OAuth2 token introspection.
///
/// This middleware validates incoming OAuth2 bearer tokens using the provided
/// [options]. If a token is active, its claims and server-auth attributes are
/// written to the request before [onValidated] and `next` run.
///
/// Only a bearer `Authorization` header is accepted. Missing, empty, or
/// non-bearer credentials, inactive or expired tokens, malformed responses,
/// and introspection failures are converted from [OAuth2Exception] to a plain
/// 401 `Unauthorized` response. Client credentials, token hints, caching, and
/// upstream requests remain controlled by [OAuthIntrospectionOptions] and
/// [OAuth2TokenIntrospector]; [httpClient] supplies the HTTP transport.
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
    try {
      await validateOAuthBearerAuthorizationAndWriteAttributes(
        authorizationHeader: ctx.request.header(
          HttpHeaders.authorizationHeader,
        ),
        introspector: introspector,
        setAttribute: ctx.request.setAttribute,
        context: ctx,
        onValidated: onValidated,
      );
    } on OAuth2Exception catch (_) {
      ctx.response
        ..statusCode = HttpStatus.unauthorized
        ..write('Unauthorized');
      return ctx.response;
    }

    return await next();
  };
}
