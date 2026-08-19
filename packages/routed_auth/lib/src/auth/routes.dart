// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:routed_auth/src/auth/manager/auth_manager.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthCredentials,
        AuthEndpointDescriptor,
        AuthOperationAuthentication,
        AuthOperationCsrfPolicy,
        AuthOperationInvocation,
        AuthFeatureSessionControl,
        AuthOperationMethod,
        AuthOperationOriginPolicy,
        AuthCallbackRouteKind,
        authErrorStatusCode,
        authProviderSummaries,
        AuthFlowException,
        AuthTwoFactorRequiredException,
        AuthProvider,
        AuthRateLimitException,
        AuthRateLimitAction,
        AuthResult,
        AuthRegisterRouteKind,
        AuthSignInRouteKind,
        AuthSessionStrategy,
        AuthSession,
        AuthUser,
        TwoFactorFeature,
        CallbackProvider,
        CredentialsProvider,
        EmailProvider,
        normalizeAuthCallbackProviderResult,
        OAuthProvider,
        respondWithSanitizedAuthRedirectOrSession,
        sanitizeAuthErrorCode,
        resolveAuthCallbackRouteDecision,
        resolveAuthRegisterRouteDecision,
        resolveAuthProviderByOptionalId,
        resolveAuthSignInRouteDecision,
        resolveAuthSignOutForStrategy,
        resolveAndSanitizeRedirectWithResolver;
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/response.dart';
import 'package:routed_core/src/router/router.dart';
import 'package:routed_http/routed_http.dart';
import 'package:routed_sessions/routed_sessions.dart';

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
/// - `POST /password-reset/request` requests a reset message when configured.
/// - `POST /password-reset/confirm` consumes a reset token.
/// - `POST /password/change` reauthenticates and changes a password.
/// - `GET /sessions` lists active server-side sessions.
/// - `POST /sessions/revoke` revokes one server-side session.
/// - `POST /sessions/revoke-others` revokes every other server-side session.
/// - `GET /2fa/status` returns the current two-factor status when enabled.
/// - `POST /2fa/enroll` starts TOTP enrollment when enabled.
/// - `POST /2fa/enroll/verify` activates TOTP and returns recovery codes.
/// - `POST /2fa/verify` verifies an enabled TOTP code.
/// - `POST /2fa/recovery-code` consumes one recovery code.
/// - `POST /2fa/recovery-codes/regenerate` replaces recovery codes.
/// - `POST /2fa/disable` disables TOTP.
/// - `POST /2fa/challenge/verify` completes a pending credential sign-in.
/// - `POST /2fa/challenge/recovery-code` completes a pending sign-in with a
///   recovery code.
/// - `POST /2fa/trusted-devices/revoke` revokes all trusted devices.
/// - `POST /2fa/step-up` verifies TOTP for a sensitive action.
/// - `POST /2fa/step-up/revoke` revokes the current step-up proof.
///
/// ## Usage
/// ```dart
/// final routes = AuthRoutes(manager);
/// routes.register(engine.defaultRouter);
/// ```
class AuthRoutes {
  AuthRoutes(AuthManager manager, {AuthManager Function()? managerOf})
    : _manager = manager,
      _managerOf = managerOf;

  final AuthManager _manager;
  final AuthManager Function()? _managerOf;

  static const String _activeOrganizationKey =
      '__routed.auth.activeOrganizationId';
  static const String _activeTeamKey = '__routed.auth.activeTeamId';

  /// Resolves the manager used by route handlers.
  ///
  /// When [managerOf] is provided (e.g. a container lookup), it is consulted on
  /// every request so handlers stay in sync with the current manager after
  /// config reloads replace the previously bound instance. Otherwise the
  /// manager passed to the constructor is used.
  AuthManager get manager => _managerOf?.call() ?? _manager;

  void register(Router router, {String? basePath}) {
    final root = basePath ?? manager.options.basePath;
    final featureEndpoints = manager.runtime.registry.endpoints
        .where((endpoint) => !endpoint.serverOnly)
        .toList(growable: false);
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
        auth.post('/callback/{provider}', _callback);
        auth.post('/signout', _signOut);
        if (manager.options.passwordResetSender != null) {
          auth.post('/password-reset/request', _passwordResetRequest);
          auth.post('/password-reset/confirm', _passwordResetConfirm);
        }
        auth.post('/password/change', _passwordChange);
        if (manager.options.sessionStrategy == AuthSessionStrategy.session) {
          auth.get('/sessions', _sessions);
          auth.post('/sessions/revoke', _revokeSession);
          auth.post('/sessions/revoke-others', _revokeOtherSessions);
        }
        // Register optional feature routes unconditionally. The handlers
        // resolve the live manager on each request, so managerOf-based config
        // reloads can activate 2FA after this route table was built.
        auth.get('/2fa/status', _twoFactorStatus);
        auth.post('/2fa/enroll', _twoFactorEnroll);
        auth.post('/2fa/enroll/verify', _twoFactorVerifyEnrollment);
        auth.post('/2fa/verify', _twoFactorVerify);
        auth.post('/2fa/recovery-code', _twoFactorRecoveryCode);
        auth.post(
          '/2fa/recovery-codes/regenerate',
          _twoFactorRegenerateRecoveryCodes,
        );
        auth.post('/2fa/disable', _twoFactorDisable);
        auth.post('/2fa/challenge/verify', _twoFactorChallengeVerify);
        auth.post(
          '/2fa/challenge/recovery-code',
          _twoFactorRecoveryChallengeVerify,
        );
        auth.post(
          '/2fa/trusted-devices/revoke',
          _twoFactorRevokeTrustedDevices,
        );
        auth.post('/2fa/step-up', _twoFactorStepUp);
        auth.post('/2fa/step-up/revoke', _twoFactorStepUpRevoke);
        for (final endpoint in featureEndpoints) {
          Future<Response> handler(EngineContext ctx) =>
              _featureOperation(ctx, endpoint);
          switch (endpoint.method) {
            case AuthOperationMethod.get:
              auth.get(endpoint.path, handler);
              break;
            case AuthOperationMethod.post:
              auth.post(endpoint.path, handler);
              break;
          }
        }
      },
    );
  }

  Future<Response> _featureOperation(
    EngineContext ctx,
    AuthEndpointDescriptor<EngineContext> endpoint,
  ) async {
    Map<String, dynamic> payload;
    try {
      payload = await _payload(ctx);
    } catch (_) {
      return _errorResponse(ctx, 'invalid_request');
    }
    if (endpoint.originPolicy == AuthOperationOriginPolicy.browser) {
      final browserError = manager.validateBrowserRequest(ctx);
      if (browserError != null) return _errorResponse(ctx, browserError);
    }
    if (endpoint.csrfPolicy == AuthOperationCsrfPolicy.required &&
        !manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    try {
      final session =
          endpoint.authentication == AuthOperationAuthentication.none
          ? null
          : await manager.resolveSession(ctx);
      if (endpoint.authentication == AuthOperationAuthentication.session &&
          session == null) {
        throw AuthFlowException('unauthorized');
      }
      final operation = endpoint.rateLimitOperation;
      if (operation != null) {
        await manager.enforceRateLimitOperation(
          ctx,
          operation: operation,
          identifier: session?.user.id,
        );
      }
      final mutableSession =
          manager.options.sessionStrategy == AuthSessionStrategy.session &&
          ctx.hasSession;
      final activeOrganizationId = mutableSession
          ? ctx.getSession<String>(_activeOrganizationKey)
          : null;
      final activeTeamId = mutableSession
          ? ctx.getSession<String>(_activeTeamKey)
          : null;
      final featureSessionControl = _RoutedFeatureSessionControl(
        manager,
        ctx,
        currentSessionId:
            manager.options.sessionStrategy == AuthSessionStrategy.session
            ? await manager.currentStoredSessionId(ctx)
            : null,
      );
      final response = await endpoint.invoke(
        AuthOperationInvocation<EngineContext>(
          context: ctx,
          user: session?.user,
          emailVerified: session?.user.attributes['emailVerified'] == true,
          activeOrganizationId: activeOrganizationId,
          activeTeamId: activeTeamId,
          writeActiveSelection: mutableSession
              ? (organizationId, teamId) {
                  if (organizationId == null) {
                    ctx.session.values.remove(_activeOrganizationKey);
                  } else {
                    ctx.setSession(_activeOrganizationKey, organizationId);
                  }
                  if (teamId == null) {
                    ctx.session.values.remove(_activeTeamKey);
                  } else {
                    ctx.setSession(_activeTeamKey, teamId);
                  }
                }
              : null,
          sessionControl: featureSessionControl,
        ),
        payload,
      );
      return ctx.json(response);
    } on AuthFlowException catch (error) {
      if (!payload.containsKey('organizationId') &&
          ctx.hasSession &&
          (error.code == 'organization_not_found' ||
              error.code == 'organization_forbidden')) {
        ctx.session.values
          ..remove(_activeOrganizationKey)
          ..remove(_activeTeamKey);
      }
      return _flowErrorResponse(ctx, error);
    } catch (_) {
      return _errorResponse(ctx, 'auth_request_failed');
    }
  }

  Future<Response> _providers(EngineContext ctx) async {
    return ctx.json({
      'providers': authProviderSummaries(manager.options.providers),
    });
  }

  Future<Response> _csrf(EngineContext ctx) async {
    return ctx.json({'csrfToken': manager.csrfToken(ctx)});
  }

  Future<Response> _session(EngineContext ctx) async {
    try {
      final session = await manager.resolveSession(ctx);
      if (session == null) {
        return ctx.json(null);
      }
      final payload = await manager.buildSessionPayload(ctx, session);
      return ctx.json(payload);
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _signIn(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    final provider = resolveAuthProviderByOptionalId(
      manager.options.providers,
      providerId,
    );
    if (ctx.request.method != 'GET' && provider is! OAuthProvider) {
      final browserError = manager.validateBrowserRequest(ctx);
      if (browserError != null) return _errorResponse(ctx, browserError);
    }
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
        try {
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
        } on AuthFlowException catch (error) {
          return _flowErrorResponse(ctx, error);
        }
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
          return _flowErrorResponse(ctx, error);
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
        } on AuthTwoFactorRequiredException catch (error) {
          return ctx.json({
            'status': 'two_factor_required',
            'challengeToken': error.challenge.token,
            'expiresAt': error.challenge.expiresAt.toUtc().toIso8601String(),
          }, statusCode: HttpStatus.accepted);
        } on AuthFlowException catch (error) {
          return _flowErrorResponse(ctx, error);
        }
    }
  }

  Future<Response> _register(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    final provider = resolveAuthProviderByOptionalId(
      manager.options.providers,
      providerId,
    );
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
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
          return _flowErrorResponse(ctx, error);
        }
    }
  }

  Future<Response> _callback(EngineContext ctx) async {
    final providerId = ctx.param('provider');
    final provider = resolveAuthProviderByOptionalId(
      manager.options.providers,
      providerId,
    );
    // OAuth providers such as Apple use `response_mode=form_post`, delivering
    // the authorization code and state in the POST body rather than the query
    // string. Merge the parsed payload so callback decisions see both sources.
    final params = <String, dynamic>{...ctx.request.queryParameters};
    if (ctx.method == 'POST') {
      params.addAll(await _payload(ctx));
    }
    final decision = resolveAuthCallbackRouteDecision(
      providerId: providerId,
      provider: provider,
      query: params,
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
          return _flowErrorResponse(ctx, error);
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
          return _flowErrorResponse(ctx, error);
        }
      case AuthCallbackRouteKind.custom:
        final callbackProvider = provider as CallbackProvider;
        try {
          await manager.enforceRateLimit(
            ctx,
            callbackProvider,
            action: AuthRateLimitAction.customCallback,
          );
          final callbackResult = await callbackProvider.handleCallback(
            ctx,
            params.map((key, value) => MapEntry(key, value.toString())),
          );
          final outcome = normalizeAuthCallbackProviderResult(callbackResult);
          if (!outcome.isSuccess) {
            return ctx.json({
              'error': sanitizeAuthErrorCode(outcome.errorCode),
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
          return _flowErrorResponse(ctx, error);
        } catch (_) {
          return ctx.json({
            'error': 'callback_error',
          }, statusCode: HttpStatus.badRequest);
        }
    }
  }

  Future<Response> _signOut(EngineContext ctx) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
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
      jwtCookieSecure: manager.options.jwtOptions.secure,
      jwtCookieSameSite: manager.options.jwtOptions.sameSite,
      logoutSession: () => manager.logout(ctx),
    );
    final expiredJwtCookie = signOutResolution.expiredJwtCookie;
    if (expiredJwtCookie != null) {
      ctx.response.cookies.add(expiredJwtCookie);
    }

    await manager.emitSignOut(ctx, session: session);
    return ctx.json({'ok': true});
  }

  Future<Response> _passwordResetRequest(EngineContext ctx) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }
    final email = payload['email']?.toString();
    if (email == null || email.trim().isEmpty) {
      return _errorResponse(ctx, 'invalid_email');
    }

    try {
      await manager.requestPasswordReset(ctx, email);
    } on AuthRateLimitException catch (error) {
      return _flowErrorResponse(ctx, error);
    } on AuthFlowException catch (error) {
      if (error.code == 'invalid_email') {
        return _errorResponse(ctx, error.code);
      }
      // Keep configuration and user existence indistinguishable at this
      // public boundary.
    } catch (_) {
      // Delivery failures must not turn into an account-enumeration oracle.
    }

    return ctx.json({
      'status': 'password_reset_requested',
    }, statusCode: HttpStatus.accepted);
  }

  Future<Response> _passwordResetConfirm(EngineContext ctx) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }
    final token = payload['token']?.toString();
    final newPassword = payload['newPassword']?.toString();
    if (token == null || token.trim().isEmpty) {
      return _errorResponse(ctx, 'invalid_password_reset_token');
    }
    if (newPassword == null) {
      return _errorResponse(ctx, 'password_reset_failed');
    }

    try {
      await manager.confirmPasswordReset(
        ctx,
        token: token,
        newPassword: newPassword,
      );
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    } catch (_) {
      return _errorResponse(ctx, 'password_reset_failed');
    }

    return ctx.json({'status': 'password_reset_complete'});
  }

  Future<Response> _passwordChange(EngineContext ctx) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }
    final identifier = payload['identifier']?.toString();
    final currentPassword = payload['currentPassword']?.toString();
    final newPassword = payload['newPassword']?.toString();
    if (identifier == null || currentPassword == null || newPassword == null) {
      return _errorResponse(ctx, 'password_change_failed');
    }

    try {
      await manager.changePassword(
        ctx,
        identifier: identifier,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    } catch (_) {
      return _errorResponse(ctx, 'password_change_failed');
    }

    return ctx.json({'status': 'password_changed'});
  }

  Future<Response> _sessions(EngineContext ctx) async {
    try {
      final sessions = await manager.listSessions(ctx);
      return ctx.json({
        'sessions': sessions.map((session) => session.toJson()).toList(),
      });
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _revokeSession(EngineContext ctx) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }
    final sessionId = payload['sessionId']?.toString();
    if (sessionId == null || sessionId.trim().isEmpty) {
      return _errorResponse(ctx, 'session_not_found');
    }
    try {
      await manager.revokeSession(ctx, sessionId);
      return ctx.json({'status': 'session_revoked'});
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _revokeOtherSessions(EngineContext ctx) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }
    try {
      final revoked = await manager.revokeOtherSessions(ctx);
      return ctx.json({'status': 'other_sessions_revoked', 'revoked': revoked});
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorStatus(EngineContext ctx) async {
    try {
      final userId = await _twoFactorUserId(ctx);
      final feature = manager.twoFactor;
      if (feature == null) {
        return await _errorResponse(ctx, 'two_factor_unavailable');
      }
      final status = await feature.status(userId);
      return ctx.json(status.toJson());
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorEnroll(EngineContext ctx) async {
    final payload = await _payload(ctx);
    final protectionError = await _twoFactorProtectionError(ctx, payload);
    if (protectionError != null) return protectionError;
    try {
      final userId = await _twoFactorUserId(ctx);
      final feature = manager.twoFactor;
      if (feature == null) {
        return await _errorResponse(ctx, 'two_factor_unavailable');
      }
      final enrollment = await feature.beginEnrollment(
        userId,
        accountLabel: payload['accountLabel']?.toString(),
      );
      return ctx.json(enrollment.toJson());
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorVerifyEnrollment(EngineContext ctx) async {
    return _twoFactorCodeAction(ctx, (feature, userId, code) async {
      final recovery = await feature.verifyEnrollment(userId, code);
      return ctx.json({'enabled': true, ...recovery.toJson()});
    });
  }

  Future<Response> _twoFactorVerify(EngineContext ctx) async {
    return _twoFactorCodeAction(ctx, (feature, userId, code) async {
      await feature.verifyTotp(userId, code);
      return ctx.json({'verified': true});
    });
  }

  Future<Response> _twoFactorRecoveryCode(EngineContext ctx) async {
    return _twoFactorCodeAction(ctx, (feature, userId, code) async {
      await feature.useRecoveryCode(userId, code);
      return ctx.json({'verified': true, 'method': 'recovery_code'});
    }, fieldName: 'recoveryCode');
  }

  Future<Response> _twoFactorRegenerateRecoveryCodes(EngineContext ctx) async {
    return _twoFactorCodeAction(ctx, (feature, userId, code) async {
      final recovery = await feature.regenerateRecoveryCodes(userId, code);
      return ctx.json(recovery.toJson());
    });
  }

  Future<Response> _twoFactorDisable(EngineContext ctx) async {
    return _twoFactorCodeAction(ctx, (feature, userId, code) async {
      await feature.disable(userId, code);
      return ctx.json({'disabled': true});
    });
  }

  Future<Response> _twoFactorChallengeVerify(EngineContext ctx) async {
    final payload = await _payload(ctx);
    final protectionError = await _twoFactorProtectionError(ctx, payload);
    if (protectionError != null) return protectionError;
    final challengeToken = payload['challengeToken']?.toString().trim();
    final code = payload['code']?.toString().trim();
    final trustDevice = payload['trustDevice'] == true;
    if (challengeToken == null ||
        challengeToken.isEmpty ||
        code == null ||
        code.isEmpty) {
      return _errorResponse(ctx, 'two_factor_invalid_challenge');
    }
    try {
      final result = await manager.completeTwoFactorSignIn(
        ctx,
        challengeToken: challengeToken,
        code: code,
        trustDevice: trustDevice,
      );
      return await _respond(ctx, result);
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorRevokeTrustedDevices(EngineContext ctx) async {
    final payload = await _payload(ctx);
    final protectionError = await _twoFactorProtectionError(ctx, payload);
    if (protectionError != null) return protectionError;
    try {
      await manager.revokeTwoFactorTrustedDevices(ctx);
      return ctx.json({'status': 'trusted_devices_revoked'});
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorRecoveryChallengeVerify(EngineContext ctx) async {
    final payload = await _payload(ctx);
    final protectionError = await _twoFactorProtectionError(ctx, payload);
    if (protectionError != null) return protectionError;
    final challengeToken = payload['challengeToken']?.toString().trim();
    final recoveryCode = payload['recoveryCode']?.toString().trim();
    if (challengeToken == null ||
        challengeToken.isEmpty ||
        recoveryCode == null ||
        recoveryCode.isEmpty) {
      return _errorResponse(ctx, 'two_factor_invalid_challenge');
    }
    try {
      final result = await manager.completeTwoFactorRecoverySignIn(
        ctx,
        challengeToken: challengeToken,
        recoveryCode: recoveryCode,
      );
      return await _respond(ctx, result);
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorStepUp(EngineContext ctx) async {
    return _twoFactorCodeAction(ctx, (feature, userId, code) async {
      final token = await manager.verifyTwoFactorStepUp(ctx, code: code);
      return ctx.json(token.toJson());
    });
  }

  Future<Response> _twoFactorStepUpRevoke(EngineContext ctx) async {
    final payload = await _payload(ctx);
    final protectionError = await _twoFactorProtectionError(ctx, payload);
    if (protectionError != null) return protectionError;
    try {
      await manager.revokeTwoFactorStepUp(ctx);
      return ctx.json({'status': 'step_up_revoked'});
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response> _twoFactorCodeAction(
    EngineContext ctx,
    Future<Response> Function(
      TwoFactorFeature<EngineContext> feature,
      String userId,
      String code,
    )
    action, {
    String fieldName = 'code',
  }) async {
    final payload = await _payload(ctx);
    final protectionError = await _twoFactorProtectionError(ctx, payload);
    if (protectionError != null) return protectionError;
    final code = payload[fieldName]?.toString().trim();
    if (code == null || code.isEmpty) {
      return _errorResponse(ctx, 'two_factor_invalid_code');
    }
    try {
      final userId = await _twoFactorUserId(ctx);
      final feature = manager.twoFactor;
      if (feature == null) {
        return await _errorResponse(ctx, 'two_factor_unavailable');
      }
      return await action(feature, userId, code);
    } on AuthFlowException catch (error) {
      return _flowErrorResponse(ctx, error);
    }
  }

  Future<Response?> _twoFactorProtectionError(
    EngineContext ctx,
    Map<String, dynamic> payload,
  ) async {
    final browserError = manager.validateBrowserRequest(ctx);
    if (browserError != null) return _errorResponse(ctx, browserError);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }
    try {
      await manager.enforceRateLimitForProviderId(
        ctx,
        'two-factor',
        action: AuthRateLimitAction.twoFactor,
      );
    } on AuthFlowException catch (error) {
      return await _flowErrorResponse(ctx, error);
    }
    return null;
  }

  Future<String> _twoFactorUserId(EngineContext ctx) async {
    final session = await manager.resolveSession(ctx);
    final userId = session?.user.id.trim() ?? '';
    if (userId.isEmpty) throw AuthFlowException('unauthorized');
    return userId;
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

  Future<Response> _errorResponse(EngineContext ctx, String code) async {
    return ctx.json({'error': code}, statusCode: authErrorStatusCode(code));
  }

  Future<Response> _flowErrorResponse(
    EngineContext ctx,
    AuthFlowException error,
  ) async {
    if (error is AuthRateLimitException) {
      final retryAfter = error.retryAfter.inSeconds.clamp(1, 2147483647);
      ctx.response.headers.set(
        HttpHeaders.retryAfterHeader,
        retryAfter.toString(),
      );
    }
    return ctx.json(
      {'error': sanitizeAuthErrorCode(error.code)},
      statusCode: error is AuthRateLimitException
          ? HttpStatus.tooManyRequests
          : HttpStatus.unauthorized,
    );
  }
}

final class _RoutedFeatureSessionControl implements AuthFeatureSessionControl {
  const _RoutedFeatureSessionControl(
    this.manager,
    this.context, {
    required this.currentSessionId,
  });

  final AuthManager manager;
  final EngineContext context;

  @override
  final String? currentSessionId;

  @override
  AuthSessionStrategy get strategy => manager.options.sessionStrategy;

  @override
  Future<AuthSession> replaceIdentity(
    AuthUser user, {
    required String authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  }) => manager.replaceFeatureSession(
    context,
    user,
    authenticationMethod: authenticationMethod,
    maximumAge: maximumAge,
    impersonatedBy: impersonatedBy,
  );

  @override
  Future<void> signOut() => manager.signOutFeatureSession(context);
}
