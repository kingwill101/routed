import 'dart:convert';
import 'dart:io';

import 'package:routed/src/auth/auth_manager.dart';
import 'package:routed/src/auth/auth_models.dart';
import 'package:routed/src/auth/auth_providers.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/router.dart';

/// Auth HTTP routes for routed.
///
/// ## Routes
/// - `GET /providers` lists configured providers.
/// - `GET /csrf` issues CSRF tokens.
/// - `GET /session` returns the current session.
/// - `GET|POST /signin/{provider}` begins sign-in.
/// - `POST /register/{provider}` registers new credentials.
/// - `GET /callback/{provider}` completes OAuth/email flows.
/// - `POST /signout` signs the user out.
///
/// ## Usage
/// ```dart
/// final routes = AuthRoutes(manager);
/// routes.register(engine.defaultRouter);
/// ```
class AuthRoutes {
  AuthRoutes(this.manager);

  final AuthManager manager;

  void register(Router router, {String? basePath}) {
    final root = basePath ?? manager.options.basePath;
    router.group(
      path: root,
      builder: (auth) {
        auth.get('/providers', _providers);
        auth.get('/csrf', _csrf);
        auth.get('/session', _session);
        auth.post('/signin/{provider}', _signIn);
        auth.get('/signin/{provider}', _signIn);
        auth.post('/register/{provider}', _register);
        auth.get('/callback/{provider}', _callback);
        auth.post('/signout', _signOut);
      },
    );
  }

  Response _providers(EngineContext ctx) {
    return ctx.json({'providers': manager.providerSummaries()});
  }

  Response _csrf(EngineContext ctx) {
    return ctx.json({'csrfToken': manager.csrfToken(ctx)});
  }

  Future<Response> _session(EngineContext ctx) async {
    final session = await manager.resolveSession(ctx);
    return ctx.json(session?.toJson());
  }

  Future<Response> _signIn(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    if (providerId == null || providerId.isEmpty) {
      return ctx.json({
        'error': 'missing_provider',
      }, statusCode: HttpStatus.badRequest);
    }

    final provider = manager.resolveProvider(providerId);
    if (provider == null) {
      return ctx.json({
        'error': 'unknown_provider',
      }, statusCode: HttpStatus.notFound);
    }

    final payload = await _payload(ctx);
    final callbackUrl = _callbackUrl(ctx, payload);

    if (provider is OAuthProvider) {
      final redirectUri = await manager.beginOAuth(
        ctx,
        provider,
        callbackUrl: callbackUrl,
      );
      return await ctx.redirect(redirectUri.toString());
    }

    if (ctx.request.method == 'GET') {
      return ctx.json({
        'error': 'method_not_allowed',
      }, statusCode: HttpStatus.methodNotAllowed);
    }

    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    if (provider is EmailProvider) {
      final email = payload['email']?.toString();
      if (email == null || email.isEmpty) {
        return ctx.json({
          'error': 'missing_email',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        await manager.signInWithEmail(ctx, provider, email, callbackUrl ?? '');
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
      return ctx.json({'status': 'verification_sent', 'email': email});
    }

    if (provider is CredentialsProvider) {
      final credentials = AuthCredentials.fromMap(payload);
      try {
        final result = await manager.signInWithCredentials(
          ctx,
          provider,
          credentials,
        );
        return await _respond(ctx, result);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    return ctx.json({
      'error': 'unsupported_provider',
    }, statusCode: HttpStatus.badRequest);
  }

  Future<Response> _register(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    if (providerId == null || providerId.isEmpty) {
      return ctx.json({
        'error': 'missing_provider',
      }, statusCode: HttpStatus.badRequest);
    }

    final provider = manager.resolveProvider(providerId);
    if (provider == null) {
      return ctx.json({
        'error': 'unknown_provider',
      }, statusCode: HttpStatus.notFound);
    }

    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    if (provider is CredentialsProvider) {
      final credentials = AuthCredentials.fromMap(payload);
      try {
        final result = await manager.registerWithCredentials(
          ctx,
          provider,
          credentials,
        );
        return await _respond(ctx, result);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    return ctx.json({
      'error': 'unsupported_provider',
    }, statusCode: HttpStatus.badRequest);
  }

  Future<Response> _callback(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    if (providerId == null || providerId.isEmpty) {
      return ctx.json({
        'error': 'missing_provider',
      }, statusCode: HttpStatus.badRequest);
    }

    final provider = manager.resolveProvider(providerId);
    if (provider == null) {
      return ctx.json({
        'error': 'unknown_provider',
      }, statusCode: HttpStatus.notFound);
    }

    if (provider is OAuthProvider) {
      final code = ctx.request.queryParameters['code'];
      final state = ctx.request.queryParameters['state'];
      if (code == null || code.isEmpty) {
        return ctx.json({
          'error': 'missing_code',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        final result = await manager.finishOAuth(ctx, provider, code, state);
        return await _respond(ctx, result);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    if (provider is EmailProvider) {
      final token = ctx.request.queryParameters['token'];
      final email =
          ctx.request.queryParameters['email'] ??
          ctx.request.queryParameters['identifier'];
      if (token == null || token.isEmpty || email == null || email.isEmpty) {
        return ctx.json({
          'error': 'missing_token',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        final result = await manager.verifyEmail(ctx, provider, email, token);
        return await _respond(ctx, result);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    return ctx.json({
      'error': 'unsupported_provider',
    }, statusCode: HttpStatus.badRequest);
  }

  Future<Response> _signOut(EngineContext ctx) async {
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    switch (manager.options.sessionStrategy) {
      case AuthSessionStrategy.session:
        await manager.sessionAuth.logout(ctx);
        break;
      case AuthSessionStrategy.jwt:
        final cookie = Cookie(manager.options.jwtOptions.cookieName, '')
          ..maxAge = 0
          ..path = '/';
        ctx.response.cookies.add(cookie);
        break;
    }

    return ctx.json({'ok': true});
  }

  Future<Map<String, dynamic>> _payload(EngineContext ctx) async {
    final contentType = ctx.request.contentType?.mimeType ?? '';
    if (contentType.contains('application/json')) {
      final body = await ctx.request.body();
      if (body.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'value': decoded};
    }
    if (contentType.contains('application/x-www-form-urlencoded') ||
        contentType.contains('multipart/form-data')) {
      return await ctx.formCache;
    }

    return Map<String, dynamic>.from(ctx.queryCache);
  }

  String? _callbackUrl(EngineContext ctx, Map<String, dynamic> payload) {
    final candidate =
        payload['callbackUrl']?.toString() ??
        payload['redirect']?.toString() ??
        ctx.request.queryParameters['callbackUrl'];
    return _sanitizeRedirect(ctx, candidate);
  }

  String? _sanitizeRedirect(EngineContext ctx, String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      return null;
    }
    if (!uri.isAbsolute) {
      if (!value.startsWith('/')) {
        return null;
      }
      return value;
    }

    final requestUri = ctx.request.uri;
    final sameHost = uri.host == requestUri.host;
    final sameScheme =
        uri.scheme.isEmpty || uri.scheme.toLowerCase() == requestUri.scheme;
    if (sameHost && sameScheme) {
      return uri.toString();
    }
    return null;
  }

  Future<Response> _respond(EngineContext ctx, AuthResult result) async {
    if (result.redirectUrl != null && result.redirectUrl!.isNotEmpty) {
      return await ctx.redirect(result.redirectUrl!);
    }
    return ctx.json(result.session.toJson());
  }
}
