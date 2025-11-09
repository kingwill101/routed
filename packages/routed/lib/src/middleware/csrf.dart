import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:routed/middlewares.dart' show Middleware, Next;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart' show SessionConfig;

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

bool _isSecureRequest(EngineContext ctx) {
  if (ctx.request.uri.scheme == 'https') {
    return true;
  }

  final config = ctx.engineConfig;
  if (!config.features.enableProxySupport) {
    return false;
  }

  final remoteAddress = ctx.request.httpRequest.connectionInfo?.remoteAddress;
  if (remoteAddress == null) {
    return false;
  }

  if (!config.isTrustedProxy(remoteAddress)) {
    return false;
  }

  bool matchesHttps(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    final candidates = value
        .split(',')
        .map((entry) => entry.trim().toLowerCase())
        .where((entry) => entry.isNotEmpty);
    for (final candidate in candidates) {
      final normalized = candidate.replaceAll('"', '');
      if (normalized == 'https' || normalized == 'https://') {
        return true;
      }
    }
    return false;
  }

  final forwardedProto = ctx.requestHeader('X-Forwarded-Proto');
  if (matchesHttps(forwardedProto)) {
    return true;
  }

  final forwardedScheme = ctx.requestHeader('X-Forwarded-Scheme');
  if (matchesHttps(forwardedScheme)) {
    return true;
  }

  final cloudFrontProto = ctx.requestHeader('CloudFront-Forwarded-Proto');
  if (matchesHttps(cloudFrontProto)) {
    return true;
  }

  final forwarded = ctx.requestHeader('Forwarded');
  if (forwarded != null && forwarded.isNotEmpty) {
    final segments = forwarded
        .split(',')
        .expand((segment) => segment.split(';'))
        .map((pair) => pair.trim().toLowerCase());

    for (final segment in segments) {
      if (segment.startsWith('proto=')) {
        final value = segment
            .substring('proto='.length)
            .trim()
            .replaceAll('"', '');
        if (value == 'https') {
          return true;
        }
      }
    }
  }

  final frontEndHttps = ctx.requestHeader('Front-End-Https');
  if (frontEndHttps != null && frontEndHttps.toLowerCase() == 'on') {
    return true;
  }

  final xForwardedSsl = ctx.requestHeader('X-Forwarded-Ssl');
  if (xForwardedSsl != null && xForwardedSsl.toLowerCase() == 'on') {
    return true;
  }

  return false;
}
