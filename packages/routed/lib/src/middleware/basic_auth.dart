import 'dart:convert';
import 'dart:io';

import '../context/context.dart';
import '../router/types.dart';

/// A typedef for a map that holds authentication accounts.
/// The key is the username and the value is the password.
typedef AuthAccounts = Map<String, String>;

/// Middleware function for basic authentication.
///
/// This function takes a map of accounts and returns a middleware function
/// that can be used to protect routes with basic authentication.
///
/// The middleware checks the `Authorization` header of the incoming request.
/// If the header is missing or does not contain valid credentials, it responds
/// with a 401 Unauthorized status and an error message.
///
/// If the credentials are valid, it sets the username in the context and
/// proceeds to the next middleware or handler.
Middleware basicAuth(
  AuthAccounts accounts, {
  String realm = 'Restricted Area',
}) {
  return (EngineContext ctx, Next next) async {
    final authHeader = ctx.headers.value(HttpHeaders.authorizationHeader);

    if (authHeader == null || !authHeader.startsWith('Basic ')) {
      ctx.response.headers.set('WWW-Authenticate', 'Basic realm="$realm"');
      return ctx.errorResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Unauthorized',
      );
    }

    final encodedCredentials = authHeader.substring(6).trim();
    final credentials = utf8
        .decode(base64.decode(encodedCredentials))
        .split(':');

    if (credentials.length != 2 ||
        !accounts.containsKey(credentials[0]) ||
        !_timingSafeEquals(accounts[credentials[0]]!, credentials[1])) {
      ctx.response.headers.set('WWW-Authenticate', 'Basic realm="$realm"');
      return ctx.errorResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Unauthorized',
      );
    }

    ctx.set('user', credentials[0]);
    return await next();
  };
}

bool _timingSafeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}
