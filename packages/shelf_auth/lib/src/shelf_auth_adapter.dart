import 'dart:async';
import 'dart:convert';

import 'package:server_auth/server_auth.dart';
import 'package:shelf/shelf.dart';

const String shelfAuthPrincipalContextKey = 'shelf_auth.principal';
const String shelfAuthTokenContextKey = 'shelf_auth.bearer_token';

typedef ShelfPrincipalResolver =
    FutureOr<AuthPrincipal?> Function(String token, Request request);

/// Returns the authenticated principal stored on the request context.
AuthPrincipal? authPrincipal(
  Request request, {
  String contextKey = shelfAuthPrincipalContextKey,
}) {
  final value = request.context[contextKey];
  if (value is AuthPrincipal) {
    return value;
  }
  return null;
}

/// Reads a bearer token from the `Authorization` header.
String? bearerToken(Request request) {
  return extractBearerToken(
    request.headers['authorization'],
    caseSensitive: false,
  );
}

/// Resolves bearer tokens into [AuthPrincipal] values.
///
/// When [strict] is true, missing or invalid bearer tokens return 401.
Middleware bearerAuth({
  required ShelfPrincipalResolver resolvePrincipal,
  bool strict = false,
  String principalContextKey = shelfAuthPrincipalContextKey,
  String tokenContextKey = shelfAuthTokenContextKey,
}) {
  return (innerHandler) {
    return (request) async {
      final token = bearerToken(request);
      if (token == null) {
        if (strict) {
          return _unauthorized('missing_bearer_token', realm: 'Restricted');
        }
        return innerHandler(request);
      }

      final principal = await resolvePrincipal(token, request);
      if (principal == null) {
        if (strict) {
          return _unauthorized('invalid_bearer_token', realm: 'Restricted');
        }
        return innerHandler(request);
      }

      final next = request.change(
        context: <String, Object>{
          ...request.context,
          principalContextKey: principal,
          tokenContextKey: token,
        },
      );
      return innerHandler(next);
    };
  };
}

/// Exposes configured auth providers on a Shelf route.
///
/// Default route is `/auth/providers`.
Middleware authProvidersEndpoint({
  required Iterable<AuthProvider> providers,
  String path = '/auth/providers',
}) {
  final normalizedPath = _normalizePath(path);
  final payload = jsonEncode(<String, Object>{
    'providers': authProviderSummaries(providers),
  });

  return (innerHandler) {
    return (request) {
      if (request.method == 'GET' && request.url.path == normalizedPath) {
        return Response.ok(
          payload,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      return innerHandler(request);
    };
  };
}

/// Requires an authenticated principal on the request context.
///
/// Use together with [bearerAuth] or another middleware that writes
/// `AuthPrincipal` into the request context.
Middleware requireAuthenticated({
  String principalContextKey = shelfAuthPrincipalContextKey,
  String realm = 'Restricted',
}) {
  final guard = requireAuthenticatedGuard<Request, Response>(
    principalResolver: (request) =>
        authPrincipal(request, contextKey: principalContextKey),
    onDenied: (_) => _unauthorized('authentication_required', realm: realm),
  );

  return (innerHandler) {
    return (request) async {
      final result = await guard(request);
      if (!result.allowed) {
        return result.response ??
            _unauthorized('authentication_required', realm: realm);
      }
      return innerHandler(request);
    };
  };
}

/// Requires the current principal to include the expected [roles].
///
/// Returns:
/// - `401` when unauthenticated
/// - `403` when authenticated but missing required role(s)
Middleware requireRoles(
  Iterable<String> roles, {
  bool any = false,
  String principalContextKey = shelfAuthPrincipalContextKey,
  String realm = 'Restricted',
}) {
  final guard = requireRolesGuard<Request, Response>(
    roles,
    principalResolver: (request) =>
        authPrincipal(request, contextKey: principalContextKey),
    any: any,
    onUnauthenticated: (_) =>
        _unauthorized('authentication_required', realm: realm),
    onForbidden: (_) => _forbidden('insufficient_role'),
  );

  return (innerHandler) {
    return (request) async {
      final result = await guard(request);
      if (!result.allowed) {
        return result.response ?? _forbidden('insufficient_role');
      }
      return innerHandler(request);
    };
  };
}

String _normalizePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '';
  }
  var normalized = trimmed;
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

Response _unauthorized(String code, {required String realm}) {
  return Response(
    401,
    body: jsonEncode(<String, String>{'error': code}),
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'www-authenticate': buildBearerAuthenticateHeader(realm: realm),
    },
  );
}

Response _forbidden(String code) {
  return Response(
    403,
    body: jsonEncode(<String, String>{'error': code}),
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}
