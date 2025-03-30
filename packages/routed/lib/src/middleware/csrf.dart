import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:routed/src/context/context.dart';

import '../../middlewares.dart';

Middleware csrfMiddleware() {
  return (EngineContext ctx) async {
    final config = ctx.engineConfig;

    if (!config.security.csrfProtection ||
        !config.features.enableSecurityFeatures) {
      await ctx.next();
      return;
    }

    final request = ctx.request;
    final response = ctx.response;

    if (request.method == 'GET' || request.method == 'HEAD') {
      // Generate and set CSRF token
      final token = generateCsrfToken(); // Implement this function (see below)
      ctx.setSession(config.security.csrfCookieName, token);
      ctx.setCookie(config.security.csrfCookieName, token,
          httpOnly: true, secure: true, sameSite: SameSite.strict);
      await ctx.next();
      return;
    }

    // For state-changing methods, verify the token
    final cookieToken = ctx.cookie(config.security.csrfCookieName)?.value;
    final sessionToken = await ctx.getSession('csrf_token') as String?;
    final requestToken =
        (await ctx.postForm('_csrf'));

    if (cookieToken == null ||
        sessionToken == null ||
        cookieToken != sessionToken ||
        requestToken != sessionToken) {
      ctx.abortWithStatus(HttpStatus.forbidden, 'CSRF token mismatch');
      return;
    }

    await ctx.next();
  };
}

String generateCsrfToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(bytes);
}
