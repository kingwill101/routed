import 'dart:io';

import 'package:routed/middlewares.dart' show Middleware, Next;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart' show SessionConfig;
import 'package:routed_security/routed_security.dart' as security;

Middleware csrfMiddleware() {
  return (EngineContext ctx, Next next) async {
    final config = ctx.engineConfig;

    if (!config.security.csrfProtection ||
        !config.features.enableSecurityFeatures ||
        !ctx.container.has<SessionConfig>()) {
      return await next();
    }

    final request = ctx.request;

    if (security.isCsrfSafeMethod(request.method)) {
      var token = ctx.getSession<String>(config.security.csrfCookieName) ?? '';
      if (token.isEmpty) {
        token = generateCsrfToken();
        ctx.setSession(config.security.csrfCookieName, token);

        final isSecure = _isSecureRequest(ctx);
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
    final submitted = security.resolveSubmittedCsrfToken(
      headerToken: ctx.requestHeader('x-csrf-token'),
      fallbackHeaderToken: ctx.requestHeader('X-CSRF-Token'),
      formToken: await ctx.postForm('_csrf'),
    );

    if (!security.isCsrfTokenValid(
      sessionToken: sessionToken,
      submittedToken: submitted,
    )) {
      return ctx.string(
        'CSRF token mismatch',
        statusCode: HttpStatus.forbidden,
      );
    }

    return await next();
  };
}

String generateCsrfToken() => security.generateCsrfToken();

bool _isSecureRequest(EngineContext ctx) {
  final request = ctx.request;
  final config = ctx.engineConfig;
  final remoteAddress = request.httpRequest.connectionInfo?.remoteAddress;
  final isTrustedProxy =
      config.features.enableProxySupport &&
      remoteAddress != null &&
      config.isTrustedProxy(remoteAddress);

  return security.isSecureTransport(
    scheme: request.uri.scheme,
    proxySupportEnabled: config.features.enableProxySupport,
    remoteIsTrustedProxy: isTrustedProxy,
    forwardedProto: ctx.requestHeader('X-Forwarded-Proto'),
    forwardedScheme: ctx.requestHeader('X-Forwarded-Scheme'),
    cloudFrontForwardedProto: ctx.requestHeader('CloudFront-Forwarded-Proto'),
    forwarded: ctx.requestHeader('Forwarded'),
    frontEndHttps: ctx.requestHeader('Front-End-Https'),
    xForwardedSsl: ctx.requestHeader('X-Forwarded-Ssl'),
  );
}
