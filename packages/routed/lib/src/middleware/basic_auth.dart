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
Middleware basicAuth(AuthAccounts accounts) {
  return (EngineContext ctx) async {
    // Retrieve the Authorization header from the request.
    final authHeader = ctx.headers.value(HttpHeaders.authorizationHeader);

    // Check if the Authorization header is missing or does not start with 'Basic '.
    if (authHeader == null || !authHeader.startsWith('Basic ')) {
      // Respond with a 401 Unauthorized status and an error message.
      ctx.json(
        {"error": "Unauthorized"},
        statusCode: HttpStatus.unauthorized,
      );
      // Abort the request to prevent further processing.
      ctx.abort();
      return;
    }

    // Extract the base64 encoded credentials from the Authorization header.
    final encodedCredentials = authHeader.substring(6).trim();
    // Decode the base64 encoded credentials and split them into username and password.
    final credentials =
        utf8.decode(base64.decode(encodedCredentials)).split(':');

    // Check if the credentials are invalid or do not match the accounts map.
    if (credentials.length != 2 || accounts[credentials[0]] != credentials[1]) {
      // Respond with a 401 Unauthorized status and an error message.
      ctx.json(statusCode: HttpStatus.unauthorized, {"error": "Unauthorized"});
      // Abort the request to prevent further processing.
      ctx.abort();
      return;
    }

    // Set the username in the context for further use.
    ctx.set('user', credentials[0]);
    // Proceed to the next middleware or handler.
    await ctx.next();
  };
}
