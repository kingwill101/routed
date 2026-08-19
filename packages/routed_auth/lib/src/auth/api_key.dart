import 'dart:async';
import 'dart:io';

import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/response.dart';
import 'package:routed_core/src/router/types.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthApiKeyAuthentication,
        AuthApiKeyPlugin,
        AuthPrincipal,
        AuthUser,
        AuthUserStore,
        authPrincipalAttribute;

/// Request attribute containing the verified API-key metadata.
const String authApiKeyAuthenticationAttribute = 'auth.api_key';

/// Parsed API-key header state.
final class AuthApiKeyRequest {
  const AuthApiKeyRequest({this.value, this.malformed = false});

  /// The raw key when a credential was supplied and structurally valid.
  final String? value;

  /// Whether a recognized API-key scheme was supplied without a value.
  final bool malformed;
}

/// Returns the API-key authentication for the current request, if present.
AuthApiKeyAuthentication? currentApiKey(EngineContext context) => context
    .request
    .getAttribute<AuthApiKeyAuthentication?>(authApiKeyAuthenticationAttribute);

/// Authenticates requests carrying an API key.
///
/// The middleware accepts `X-API-Key: <key>` by default and also accepts
/// `Authorization: ApiKey <key>`. A missing key leaves the request untouched,
/// allowing applications to compose API-key, session, and JWT middleware. An
/// invalid supplied key returns a generic 401 response.
Middleware apiKeyAuthentication({
  required AuthApiKeyPlugin<EngineContext> plugin,
  required AuthUserStore userStore,
  String headerName = 'x-api-key',
  FutureOr<void> Function(
    EngineContext context,
    AuthApiKeyAuthentication authentication,
    AuthUser user,
  )?
  onVerified,
}) {
  final normalizedHeader = headerName.trim();
  if (normalizedHeader.isEmpty) {
    throw ArgumentError.value(headerName, 'headerName', 'must not be empty');
  }

  return (EngineContext ctx, Next next) async {
    final request = parseApiKeyRequest(ctx, headerName: normalizedHeader);
    if (request.malformed) return _invalidApiKey(ctx);
    final rawKey = request.value;
    if (rawKey == null) return next();

    final authentication = await plugin.authenticate(rawKey);
    final user = authentication == null
        ? null
        : await userStore.findById(authentication.record.userId);
    if (authentication == null || user == null) {
      return _invalidApiKey(ctx);
    }

    ctx.request.setAttribute(authApiKeyAuthenticationAttribute, authentication);
    ctx.request.setAttribute(
      authPrincipalAttribute,
      AuthPrincipal(
        id: user.id,
        roles: user.roles,
        attributes: {
          'apiKeyId': authentication.record.id,
          'apiKeyScopes': authentication.record.scopes,
        },
      ),
    );
    await onVerified?.call(ctx, authentication, user);
    return next();
  };
}

/// Reads an API key from the configured header or the standard authorization
/// scheme without accepting request-body values.
String? readApiKeyFromRequest(
  EngineContext ctx, {
  String headerName = 'x-api-key',
}) => parseApiKeyRequest(ctx, headerName: headerName).value;

/// Parses API-key headers while distinguishing a missing credential from a
/// malformed recognized authorization scheme.
AuthApiKeyRequest parseApiKeyRequest(
  EngineContext ctx, {
  String headerName = 'x-api-key',
}) {
  final direct = ctx.request.header(headerName).trim();
  if (direct.isNotEmpty) return AuthApiKeyRequest(value: direct);

  final authorization = ctx.request
      .header(HttpHeaders.authorizationHeader)
      .trim();
  if (authorization.isEmpty) return const AuthApiKeyRequest();
  final separator = RegExp(r'\s').firstMatch(authorization);
  final scheme = separator == null
      ? authorization
      : authorization.substring(0, separator.start);
  if (scheme.toLowerCase() != 'apikey') return const AuthApiKeyRequest();
  if (separator == null) return const AuthApiKeyRequest(malformed: true);
  final value = authorization.substring(separator.end).trim();
  if (value.isEmpty) return const AuthApiKeyRequest(malformed: true);
  return AuthApiKeyRequest(value: value);
}

Response _invalidApiKey(EngineContext ctx) {
  ctx.response.headers.set(
    HttpHeaders.wwwAuthenticateHeader,
    'ApiKey realm="auth"',
  );
  return ctx.json({
    'error': 'invalid_api_key',
  }, statusCode: HttpStatus.unauthorized);
}
