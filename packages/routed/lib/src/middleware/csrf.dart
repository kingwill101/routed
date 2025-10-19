import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart' show SessionConfig;

import 'package:routed/middlewares.dart' show Middleware, Next;

Middleware csrfMiddleware() {
  return (EngineContext ctx, Next next) async {
    final config = ctx.engineConfig;

    if (!config.security.csrfProtection ||
        !config.features.enableSecurityFeatures ||
        !ctx.container.has<SessionConfig>()) {
      return await next();
    }

    final request = ctx.request;

    // On safe/idempotent requests issue a token **only if one hasn't been
    // generated for this session yet**.  This prevents needless rotation which
    // breaks multi-tab scenarios.
    if (request.method == 'GET' ||
        request.method == 'HEAD' ||
        request.method == 'OPTIONS') {
      var token = ctx.getSession<String>(config.security.csrfCookieName) ?? '';
      if (token.isEmpty) {
        token = generateCsrfToken();
        ctx.setSession(config.security.csrfCookieName, token);

        // Use a relaxed SameSite policy for non-HTTPS (common in local dev)
        // while keeping `secure:true` & `strict` in production.
        final isSecure = ctx.request.uri.scheme == 'https';
        ctx.setCookie(
          config.security.csrfCookieName,
          token,
          httpOnly: true,
          secure: isSecure,
          sameSite: isSecure ? SameSite.strict : SameSite.lax,
          maxAge: const Duration(hours: 1).inSeconds,
        );
      }
      return await next();
    }

    final sessionToken = ctx.getSession<String>(config.security.csrfCookieName);

    // Accept token from either the custom header *or* the form field to be less
    // restrictive (mirrors behaviour of most frameworks).
    final headerToken =
        ctx.requestHeader('x-csrf-token') ?? ctx.requestHeader('X-CSRF-Token');
    final requestToken = headerToken?.isNotEmpty == true
        ? headerToken!
        : await ctx.postForm('_csrf');

    // Validate only that a session token exists and matches the submitted token.
    // Comparing cookie token as well can cause false negatives if transports mutate cookies.
    if (sessionToken == null ||
        requestToken.isEmpty ||
        requestToken != sessionToken) {
      return ctx.string(
        'CSRF token mismatch',
        statusCode: HttpStatus.forbidden,
      );
    }

    return await next();
  };
}

String generateCsrfToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(bytes);
}
