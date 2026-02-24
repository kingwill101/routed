import 'dart:io';

import 'package:routed/src/auth/manager/auth_manager.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthCredentials,
        AuthCallbackRouteKind,
        authErrorStatusCode,
        authProviderSummaries,
        AuthFlowException,
        AuthProvider,
        AuthResult,
        AuthRegisterRouteKind,
        AuthSignInRouteKind,
        CallbackProvider,
        CredentialsProvider,
        EmailProvider,
        normalizeAuthCallbackProviderResult,
        OAuthProvider,
        respondWithSanitizedAuthRedirectOrSession,
        resolveAuthCallbackRouteDecision,
        resolveAuthRegisterRouteDecision,
        resolveAuthProviderByOptionalId,
        resolveAuthSignInRouteDecision,
        resolveAuthSignOutForStrategy,
        resolveAndSanitizeRedirectWithResolver;
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
    return ctx.json({
      'providers': authProviderSummaries(manager.options.providers),
    });
  }

  Response _csrf(EngineContext ctx) {
    return ctx.json({'csrfToken': manager.csrfToken(ctx)});
  }

  Future<Response> _session(EngineContext ctx) async {
    final session = await manager.resolveSession(ctx);
    if (session == null) {
      return ctx.json(null);
    }
    final payload = await manager.buildSessionPayload(ctx, session);
    return ctx.json(payload);
  }

  Future<Response> _signIn(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    final provider = resolveAuthProviderByOptionalId(
      manager.options.providers,
      providerId,
    );
    final payload = await _payload(ctx);
    final decision = resolveAuthSignInRouteDecision(
      providerId: providerId,
      provider: provider,
      method: ctx.request.method,
      payload: payload,
      csrfValid: manager.validateCsrf(ctx, payload),
    );

    switch (decision.kind) {
      case AuthSignInRouteKind.error:
        return _errorResponse(ctx, decision.errorCode!);
      case AuthSignInRouteKind.oauth:
        final callbackUrl = await _callbackUrl(
          ctx,
          payload,
          provider: provider,
        );
        final redirectUri = await manager.beginOAuth(
          ctx,
          provider as OAuthProvider,
          callbackUrl: callbackUrl,
        );
        return await ctx.redirect(redirectUri.toString());
      case AuthSignInRouteKind.email:
        final callbackUrl = await _callbackUrl(
          ctx,
          payload,
          provider: provider,
        );
        final emailProvider = provider as EmailProvider;
        try {
          await manager.signInWithEmail(
            ctx,
            emailProvider,
            decision.email!,
            callbackUrl ?? '',
          );
        } on AuthFlowException catch (error) {
          return ctx.json({
            'error': error.code,
          }, statusCode: HttpStatus.unauthorized);
        }
        return ctx.json({
          'status': 'verification_sent',
          'email': decision.email,
        });
      case AuthSignInRouteKind.credentials:
        final credentials = AuthCredentials.fromMap(payload);
        final credentialsProvider = provider as CredentialsProvider;
        try {
          final result = await manager.signInWithCredentials(
            ctx,
            credentialsProvider,
            credentials,
          );
          return await _respond(ctx, result, provider: provider);
        } on AuthFlowException catch (error) {
          return ctx.json({
            'error': error.code,
          }, statusCode: HttpStatus.unauthorized);
        }
    }
  }

  Future<Response> _register(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    final provider = resolveAuthProviderByOptionalId(
      manager.options.providers,
      providerId,
    );
    final payload = await _payload(ctx);
    final decision = resolveAuthRegisterRouteDecision(
      providerId: providerId,
      provider: provider,
      csrfValid: manager.validateCsrf(ctx, payload),
    );

    switch (decision.kind) {
      case AuthRegisterRouteKind.error:
        return _errorResponse(ctx, decision.errorCode!);
      case AuthRegisterRouteKind.credentials:
        final credentials = AuthCredentials.fromMap(payload);
        final credentialsProvider = provider as CredentialsProvider;
        try {
          final result = await manager.registerWithCredentials(
            ctx,
            credentialsProvider,
            credentials,
          );
          return await _respond(ctx, result, provider: provider);
        } on AuthFlowException catch (error) {
          return ctx.json({
            'error': error.code,
          }, statusCode: HttpStatus.unauthorized);
        }
    }
  }

  Future<Response> _callback(EngineContext ctx) async {
    final providerId = ctx.param('provider');
    final provider = resolveAuthProviderByOptionalId(
      manager.options.providers,
      providerId,
    );
    final decision = resolveAuthCallbackRouteDecision(
      providerId: providerId,
      provider: provider,
      query: ctx.request.queryParameters,
    );

    switch (decision.kind) {
      case AuthCallbackRouteKind.error:
        return _errorResponse(ctx, decision.errorCode!);
      case AuthCallbackRouteKind.oauth:
        final oauthProvider = provider as OAuthProvider;
        try {
          final result = await manager.finishOAuth(
            ctx,
            oauthProvider,
            decision.code!,
            decision.state,
          );
          return await _respond(ctx, result, provider: provider);
        } on AuthFlowException catch (error) {
          return ctx.json({
            'error': error.code,
          }, statusCode: HttpStatus.unauthorized);
        }
      case AuthCallbackRouteKind.email:
        final emailProvider = provider as EmailProvider;
        try {
          final result = await manager.verifyEmail(
            ctx,
            emailProvider,
            decision.email!,
            decision.token!,
          );
          return await _respond(ctx, result, provider: provider);
        } on AuthFlowException catch (error) {
          return ctx.json({
            'error': error.code,
          }, statusCode: HttpStatus.unauthorized);
        }
      case AuthCallbackRouteKind.custom:
        final callbackProvider = provider as CallbackProvider;
        try {
          final params = ctx.request.queryParameters;
          final callbackResult = await callbackProvider.handleCallback(
            ctx,
            params,
          );
          final outcome = normalizeAuthCallbackProviderResult(callbackResult);
          if (!outcome.isSuccess) {
            return ctx.json({
              'error': outcome.errorCode,
            }, statusCode: HttpStatus.unauthorized);
          }

          final result = await manager.completeCustomCallback(
            ctx,
            callbackProvider,
            outcome.user!,
            redirectUrl: outcome.redirectUrl,
          );

          return await _respond(ctx, result, provider: provider);
        } on AuthFlowException catch (error) {
          return ctx.json({
            'error': error.code,
          }, statusCode: HttpStatus.unauthorized);
        } catch (error) {
          return ctx.json({
            'error': 'callback_error',
            'message': error.toString(),
          }, statusCode: HttpStatus.badRequest);
        }
    }
  }

  Future<Response> _signOut(EngineContext ctx) async {
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    final session = await manager.resolveSession(ctx);
    final signOutResolution = await resolveAuthSignOutForStrategy(
      strategy: manager.options.sessionStrategy,
      jwtCookieName: manager.options.jwtOptions.cookieName,
      logoutSession: () => manager.sessionAuth.logout(ctx),
    );
    final expiredJwtCookie = signOutResolution.expiredJwtCookie;
    if (expiredJwtCookie != null) {
      ctx.response.cookies.add(expiredJwtCookie);
    }

    await manager.emitSignOut(ctx, session: session);
    return ctx.json({'ok': true});
  }

  Future<Map<String, dynamic>> _payload(EngineContext ctx) async {
    final contentType = ctx.request.contentType?.mimeType ?? '';
    if (contentType.contains('application/json')) {
      final decoded = await ctx.bindJSON(<String, Object?>{});
      return Map<String, dynamic>.from(decoded);
    }
    if (contentType.contains('application/x-www-form-urlencoded') ||
        contentType.contains('multipart/form-data')) {
      return await ctx.formCache;
    }

    return Map<String, dynamic>.from(ctx.queryCache);
  }

  Future<String?> _callbackUrl(
    EngineContext ctx,
    Map<String, dynamic> payload, {
    AuthProvider? provider,
  }) async {
    return resolveAndSanitizeRedirectWithResolver(
      payload,
      ctx.request.queryParameters,
      requestUri: ctx.requestedUri,
      fallbackHost: ctx.host,
      fallbackScheme: ctx.scheme,
      resolveRedirect: (candidate) =>
          manager.resolveRedirect(ctx, candidate, provider: provider),
    );
  }

  Future<Response> _respond(
    EngineContext ctx,
    AuthResult result, {
    AuthProvider? provider,
  }) async {
    return respondWithSanitizedAuthRedirectOrSession<Response>(
      result: result,
      requestUri: ctx.requestedUri,
      fallbackHost: ctx.host,
      fallbackScheme: ctx.scheme,
      onRedirect: (redirectUrl) => ctx.redirect(redirectUrl),
      onSession: (session) async {
        final payload = await manager.buildSessionPayload(
          ctx,
          session,
          provider: provider,
        );
        return ctx.json(payload);
      },
    );
  }

  Response _errorResponse(EngineContext ctx, String code) {
    return ctx.json({'error': code}, statusCode: authErrorStatusCode(code));
  }
}
