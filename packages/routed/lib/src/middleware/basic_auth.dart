import 'dart:io';

import 'package:routed_security/routed_security.dart' as security;

import '../context/context.dart';
import '../router/types.dart';

/// A typedef for a map that holds authentication accounts.
/// The key is the username and the value is the password.
typedef AuthAccounts = Map<String, String>;

/// Middleware function for basic authentication.
Middleware basicAuth(
  AuthAccounts accounts, {
  String realm = 'Restricted Area',
}) {
  return (EngineContext ctx, Next next) async {
    final credentials = security.parseBasicAuthHeader(
      ctx.headers.value(HttpHeaders.authorizationHeader),
    );

    if (credentials == null ||
        !security.validateBasicAuthCredentials(credentials, accounts)) {
      ctx.response.headers.set(
        'WWW-Authenticate',
        security.basicAuthChallengeHeader(realm),
      );
      return ctx.errorResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Unauthorized',
      );
    }

    ctx.set('user', credentials.username);
    return await next();
  };
}
