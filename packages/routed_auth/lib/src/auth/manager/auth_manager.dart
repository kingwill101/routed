// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show
        AuthAccount,
        AuthApiKeyPlugin,
        AnonymousPlugin,
        AuthCallbacks,
        AuthCredentials,
        requireAuthorizedCredentialsRegistration,
        requireAuthorizedCredentialsSignIn,
        resolveAuthRedirectWithCallbacks,
        resolveAuthSignInResultForStrategyWithCallbacks,
        resolveAuthSessionPayloadWithCallbacks,
        resolveAuthSignInRedirectTarget,
        AuthPrincipal,
        AuthProvider,
        AuthRateLimitAction,
        AuthRateLimitOperation,
        AuthRateLimitRequest,
        enforceAuthRateLimit,
        hashOpaqueToken,
        baseUrlFromUri,
        resolveOAuthAuthorizationStart,
        resolveOAuthCallbackSignInForProvider,
        AuthResult,
        AuthSession,
        AuthSessionRecord,
        AuthSessionInfo,
        AuthSessionStrategy,
        TwoFactorPlugin,
        OrganizationPlugin,
        WebAuthnPlugin,
        AuthTwoFactorRequiredException,
        AuthTwoFactorStepUpToken,
        authJwtVersionClaim,
        AuthFlowException,
        AuthPasswordResetRequest,
        AuthPasswordResetResult,
        AuthPasswordChangeResult,
        AuthEmailChangeRequest,
        AuthAdminStoreCapabilities,
        AuthUserDataDeletionContributor,
        AuthUser,
        AuthRuntime,
        AdminPlugin,
        AuthAuthenticationPolicyPhase,
        AuthAuthenticationPolicyRequest,
        AuthStore,
        resolveAuthEmailVerificationSignIn,
        normalizeAuthEmail,
        startAuthEmailSignIn,
        resolveBearerOrCookieToken,
        resolveAuthSessionForStrategyWithCallbacks,
        resolveAuthSessionUpdateForStrategyWithCallbacks,
        resolveCsrfToken,
        validateCsrfToken,
        CallbackProvider,
        CredentialsProvider,
        EmailProvider,
        OAuthProvider,
        authSessionIssuedAtKey,
        AuthOptions,
        resolveAuthSessionMaxAgeSeconds,
        resolveAuthSessionExpiry,
        serializeAuthSessionIssuedAt,
        issueAuthPasswordResetTokenForUser,
        resetAuthPasswordWithToken,
        changeAuthPasswordForUser,
        issueAuthEmailChangeTokenForUser,
        confirmAuthEmailChange,
        requireAuthPasswordForUser,
        listAuthSessionsForUser,
        authUserEmailIsVerified,
        authUserIsDisabled,
        resolveAuthSignOutForStrategy,
        secureRandomToken;
import 'package:routed_auth/src/auth/hooks.dart';
import 'package:routed_auth/src/auth/browser_protection.dart';
import 'package:routed_auth/src/auth/api_key.dart';
import 'package:routed_auth/src/auth/session_auth.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_core/src/events/event.dart';
import 'package:routed_core/src/events/event_manager.dart';

/// High-level auth coordinator for routed.
class AuthManager {
  AuthManager(
    this.options, {
    SessionAuthService? sessionAuth,
    AuthRuntime<EngineContext>? runtime,
  }) : runtime = runtime ?? AuthRuntime<EngineContext>(options: options),
       _sessionAuth = sessionAuth,
       _httpClient = options.httpClient;

  final AuthOptions<EngineContext> options;
  final AuthRuntime<EngineContext> runtime;
  final SessionAuthService? _sessionAuth;
  http.Client? _httpClient;

  AuthStore get store => runtime.store;

  /// The configured two-factor plugin, if enabled for this runtime.
  TwoFactorPlugin<EngineContext>? get twoFactor =>
      runtime.plugin('two_factor') as TwoFactorPlugin<EngineContext>?;

  /// The configured organization plugin, if enabled for this runtime.
  OrganizationPlugin<EngineContext>? get organization =>
      runtime.plugin('organization') as OrganizationPlugin<EngineContext>?;

  /// The configured API-key plugin, if enabled for this runtime.
  AuthApiKeyPlugin<EngineContext>? get apiKeys =>
      runtime.plugin('api_key') as AuthApiKeyPlugin<EngineContext>?;

  /// The configured anonymous-account plugin, if enabled.
  AnonymousPlugin<EngineContext>? get anonymous =>
      runtime.plugin('anonymous') as AnonymousPlugin<EngineContext>?;

  /// Exchanges an enabled API key for a normal server-side session.
  ///
  /// The API key is read from request headers only and is never accepted from
  /// the request body. This boundary is deliberately restricted to the
  /// server-session strategy; JWT clients should continue using their API key
  /// directly or sign in through the configured provider.
  Future<AuthResult> exchangeApiKeyForSession(EngineContext ctx) async {
    final plugin = apiKeys;
    if (plugin == null || !plugin.sessionExchangeEnabled) {
      throw AuthFlowException('api_key_exchange_unavailable');
    }
    if (options.sessionStrategy != AuthSessionStrategy.session) {
      throw AuthFlowException('api_key_exchange_unavailable');
    }
    final request = parseApiKeyRequest(ctx);
    final rawKey = request.value;
    if (request.malformed || rawKey == null) {
      throw AuthFlowException('invalid_api_key');
    }
    final authentication = await plugin.authenticate(rawKey);
    if (authentication == null) throw AuthFlowException('invalid_api_key');
    final user = await store.users.findById(authentication.record.userId);
    if (user == null) throw AuthFlowException('invalid_api_key');
    return _completeSignIn(ctx, user, authenticationMethod: 'api_key');
  }

  /// The configured Admin plugin, if enabled for this runtime.
  AdminPlugin<EngineContext>? get admin =>
      runtime.plugin('admin') as AdminPlugin<EngineContext>?;

  /// The configured WebAuthn/passkey plugin, if enabled for this runtime.
  WebAuthnPlugin<EngineContext>? get webAuthn =>
      runtime.plugin('webauthn') as WebAuthnPlugin<EngineContext>?;

  SessionAuthService get sessionAuth => _sessionAuth ?? SessionAuth.instance;

  http.Client get httpClient => _httpClient ??= http.Client();

  AuthCallbacks<EngineContext> get callbacks => options.callbacks;

  String csrfToken(EngineContext ctx) {
    final token = resolveCsrfToken(
      existingToken: ctx.getSession<String>(options.csrfKey),
      generateToken: secureRandomToken,
    );
    ctx.setSession(options.csrfKey, token);
    return token;
  }

  bool validateCsrf(EngineContext ctx, Map<String, dynamic> payload) {
    final headerToken =
        ctx.request.headers.value('x-csrf-token') ??
        ctx.request.headers.value('X-CSRF-Token');
    return validateCsrfToken(
      expectedToken: ctx.getSession<String>(options.csrfKey),
      headerToken: headerToken,
      formToken: payload['_csrf']?.toString(),
      enforce: options.enforceCsrf,
    );
  }

  /// Returns an auth error code when browser request protections reject [ctx].
  String? validateBrowserRequest(EngineContext ctx) {
    return validateRoutedAuthBrowserRequest(ctx, options.browserProtection);
  }

  Future<AuthResult> signInWithCredentials(
    EngineContext ctx,
    CredentialsProvider provider,
    AuthCredentials credentials,
  ) async {
    await enforceRateLimit(
      ctx,
      provider,
      action: AuthRateLimitAction.signIn,
      identifier: credentials.email == null
          ? credentials.username
          : normalizeAuthEmail(credentials.email!),
    );
    final user = await requireAuthorizedCredentialsSignIn(
      store: store,
      passwordHasher: options.passwordHasher,
      provider: provider,
      context: ctx,
      credentials: credentials,
      passwordPolicy: options.passwordPolicy,
    );
    await _enforceAuthenticationPolicy(
      ctx,
      user,
      AuthAuthenticationPolicyPhase.beforeSessionIssue,
    );

    final plugin = twoFactor;
    final challenge = plugin == null
        ? null
        : await plugin.beginSignInChallenge(
            user.id,
            user: user,
            providerId: provider.id,
            credentials: credentials,
            trustedDeviceToken: _requestCookie(
              ctx,
              plugin.trustedDeviceCookieName,
            )?.value,
          );
    if (challenge != null) {
      throw AuthTwoFactorRequiredException(challenge: challenge);
    }

    return _completeSignIn(
      ctx,
      user,
      provider: provider,
      credentials: credentials,
    );
  }

  /// Completes a pending credential sign-in after TOTP verification.
  Future<AuthResult> completeTwoFactorSignIn(
    EngineContext ctx, {
    required String challengeToken,
    required String code,
    bool trustDevice = false,
  }) async {
    final plugin = twoFactor;
    if (plugin == null) {
      throw AuthFlowException('two_factor_unavailable');
    }
    final completion = await plugin.completeSignInChallenge(
      challengeToken,
      code,
      trustDevice: trustDevice,
    );
    final user =
        completion.user ?? await store.users.findById(completion.userId);
    if (user == null) {
      throw AuthFlowException('user_resolution_failed');
    }
    final provider = completion.providerId == null
        ? options.providers.whereType<CredentialsProvider>().firstWhere(
            (_) => true,
            orElse: CredentialsProvider.new,
          )
        : options.providers.firstWhere(
            (candidate) => candidate.id == completion.providerId,
            orElse: () => throw AuthFlowException('provider_resolution_failed'),
          );
    final result = await _completeSignIn(
      ctx,
      user,
      provider: provider,
      credentials: completion.credentials,
    );
    final trustedDevice = completion.trustedDevice;
    if (trustedDevice != null) {
      ctx.response.cookies.add(
        Cookie(plugin.trustedDeviceCookieName, trustedDevice.token)
          ..httpOnly = true
          ..secure = _isHttps(ctx)
          ..sameSite = SameSite.lax
          ..path = '/'
          ..expires = trustedDevice.expiresAt
          ..maxAge = plugin.trustedDeviceTtl.inSeconds,
      );
    }
    return result;
  }

  /// Completes a pending credential sign-in after recovery-code verification.
  Future<AuthResult> completeTwoFactorRecoverySignIn(
    EngineContext ctx, {
    required String challengeToken,
    required String recoveryCode,
  }) async {
    final plugin = twoFactor;
    if (plugin == null) {
      throw AuthFlowException('two_factor_unavailable');
    }
    final completion = await plugin.completeRecoverySignInChallenge(
      challengeToken,
      recoveryCode,
    );
    final user =
        completion.user ?? await store.users.findById(completion.userId);
    if (user == null) {
      throw AuthFlowException('user_resolution_failed');
    }
    final provider = completion.providerId == null
        ? options.providers.whereType<CredentialsProvider>().firstWhere(
            (_) => true,
            orElse: CredentialsProvider.new,
          )
        : options.providers.firstWhere(
            (candidate) => candidate.id == completion.providerId,
            orElse: () => throw AuthFlowException('provider_resolution_failed'),
          );
    return _completeSignIn(
      ctx,
      user,
      provider: provider,
      credentials: completion.credentials,
    );
  }

  /// Revokes all trusted devices for the current user and expires the cookie.
  Future<void> revokeTwoFactorTrustedDevices(EngineContext ctx) async {
    final plugin = twoFactor;
    if (plugin == null) {
      throw AuthFlowException('two_factor_unavailable');
    }
    final session = await resolveSession(ctx);
    final userId = session?.user.id.trim() ?? '';
    if (userId.isEmpty) throw AuthFlowException('unauthorized');
    await plugin.revokeAllTrustedDevices(userId);
    ctx.response.cookies.add(
      Cookie(plugin.trustedDeviceCookieName, '')
        ..httpOnly = true
        ..secure = _isHttps(ctx)
        ..sameSite = SameSite.lax
        ..path = '/'
        ..maxAge = 0,
    );
  }

  /// Verifies TOTP for a sensitive action and sets a short-lived proof cookie.
  Future<AuthTwoFactorStepUpToken> verifyTwoFactorStepUp(
    EngineContext ctx, {
    required String code,
  }) async {
    final plugin = twoFactor;
    if (plugin == null) {
      throw AuthFlowException('two_factor_unavailable');
    }
    final session = await resolveSession(ctx);
    final userId = session?.user.id.trim() ?? '';
    if (userId.isEmpty) throw AuthFlowException('unauthorized');
    final token = await plugin.verifyStepUp(
      userId,
      _twoFactorSessionBinding(ctx),
      code,
    );
    ctx.response.cookies.add(
      Cookie(plugin.stepUpCookieName, token.token)
        ..httpOnly = true
        ..secure = _isHttps(ctx)
        ..sameSite = SameSite.lax
        ..path = '/'
        ..expires = token.expiresAt
        ..maxAge = plugin.stepUpTtl.inSeconds,
    );
    return token;
  }

  /// Returns whether the current request carries a valid step-up proof.
  Future<bool> hasValidTwoFactorStepUp(EngineContext ctx) async {
    final plugin = twoFactor;
    if (plugin == null) return false;
    final session = await resolveSession(ctx);
    final userId = session?.user.id.trim() ?? '';
    if (userId.isEmpty) return false;
    final token = _requestCookie(ctx, plugin.stepUpCookieName)?.value;
    if (token == null || token.isEmpty) return false;
    return plugin.isStepUpValid(userId, _twoFactorSessionBinding(ctx), token);
  }

  /// Requires a recent step-up proof for the current request.
  Future<void> requireTwoFactorStepUp(EngineContext ctx) async {
    final plugin = twoFactor;
    if (plugin == null || plugin.stepUpStore == null) {
      throw AuthFlowException('two_factor_step_up_not_supported');
    }
    if (!await hasValidTwoFactorStepUp(ctx)) {
      throw AuthFlowException('two_factor_step_up_required');
    }
  }

  /// Revokes the current session's step-up proofs and expires its cookie.
  Future<void> revokeTwoFactorStepUp(EngineContext ctx) async {
    final plugin = twoFactor;
    if (plugin == null) {
      throw AuthFlowException('two_factor_unavailable');
    }
    final session = await resolveSession(ctx);
    final userId = session?.user.id.trim() ?? '';
    if (userId.isEmpty) throw AuthFlowException('unauthorized');
    await plugin.revokeStepUp(userId, _twoFactorSessionBinding(ctx));
    ctx.response.cookies.add(
      Cookie(plugin.stepUpCookieName, '')
        ..httpOnly = true
        ..secure = _isHttps(ctx)
        ..sameSite = SameSite.lax
        ..path = '/'
        ..maxAge = 0,
    );
  }

  Future<AuthResult> registerWithCredentials(
    EngineContext ctx,
    CredentialsProvider provider,
    AuthCredentials credentials,
  ) async {
    await enforceRateLimit(
      ctx,
      provider,
      action: AuthRateLimitAction.register,
      identifier: credentials.email == null
          ? credentials.username
          : normalizeAuthEmail(credentials.email!),
    );
    final user = await requireAuthorizedCredentialsRegistration(
      store: store,
      passwordHasher: options.passwordHasher,
      provider: provider,
      context: ctx,
      credentials: credentials,
      passwordPolicy: options.passwordPolicy,
    );

    return _completeSignIn(
      ctx,
      user,
      provider: provider,
      credentials: credentials,
      isNewUser: true,
    );
  }

  Future<AuthResult> signInWithEmail(
    EngineContext ctx,
    EmailProvider provider,
    String email,
    String callbackUrl,
  ) async {
    final normalizedEmail = normalizeAuthEmail(email);
    await enforceRateLimit(
      ctx,
      provider,
      action: AuthRateLimitAction.emailVerification,
      identifier: normalizedEmail,
    );
    final payload = await startAuthEmailSignIn<EngineContext>(
      store: store,
      provider: provider,
      context: ctx,
      email: normalizedEmail,
      callbackUrl: callbackUrl,
      sessionStrategy: options.sessionStrategy,
      generateToken: secureRandomToken,
      writeSession: ctx.setSession,
      callbackKey: options.callbackKey,
    );
    ctx.response.cookies.add(
      _buildEmailStateCookie(
        ctx,
        provider,
        payload.token,
        expiresAt: payload.expiresAt,
      ),
    );
    return payload.pendingResult;
  }

  /// Delivers a password-reset token through the application-owned sender.
  ///
  /// Unknown emails intentionally complete without invoking the sender. The
  /// routed HTTP route returns the same accepted response in either case.
  /// Password reset is available for both session strategies when a sender is
  /// configured.
  Future<void> requestPasswordReset(EngineContext ctx, String email) async {
    if (options.passwordResetSender == null) {
      throw AuthFlowException('password_reset_unavailable');
    }
    final normalizedEmail = normalizeAuthEmail(email);
    if (normalizedEmail.isEmpty) {
      throw AuthFlowException('invalid_email');
    }
    await enforceRateLimitForProviderId(
      ctx,
      'password-reset',
      action: AuthRateLimitAction.passwordResetRequest,
      identifier: normalizedEmail,
    );

    final user = await Future.sync(
      () => store.users.findByEmail(normalizedEmail),
    );
    if (user == null || user.email == null) {
      return;
    }

    final issuedAt = DateTime.now().toUtc();
    final token = await issueAuthPasswordResetTokenForUser(
      store: store,
      userId: user.id,
      ttl: options.passwordResetTtl,
      now: issuedAt,
    );
    if (token == null) {
      return;
    }
    await Future.sync(
      () => options.passwordResetSender!(
        AuthPasswordResetRequest<EngineContext>(
          context: ctx,
          user: user.redacted(),
          token: token,
          expiresAt: issuedAt.add(options.passwordResetTtl),
        ),
      ),
    );
  }

  /// Consumes a password-reset token and revokes the user's sessions.
  Future<AuthPasswordResetResult> confirmPasswordReset(
    EngineContext ctx, {
    required String token,
    required String newPassword,
  }) async {
    await enforceRateLimitForProviderId(
      ctx,
      'password-reset',
      action: AuthRateLimitAction.passwordResetConfirm,
    );
    return resetAuthPasswordWithToken(
      store: store,
      passwordHasher: options.passwordHasher,
      token: token,
      newPassword: newPassword,
      trustedDeviceStore: twoFactor?.trustedDeviceStore,
      passwordPolicy: options.passwordPolicy,
    );
  }

  /// Reauthenticates the current user, changes their password, and revokes
  /// every server-side session or JWT version for that user.
  Future<AuthPasswordChangeResult> changePassword(
    EngineContext ctx, {
    required String identifier,
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = await resolveSession(ctx);
    if (session == null) {
      throw AuthFlowException('not_authenticated');
    }
    final result = await changeAuthPasswordForUser(
      store: store,
      passwordHasher: options.passwordHasher,
      userId: session.user.id,
      identifier: identifier,
      currentPassword: currentPassword,
      newPassword: newPassword,
      trustedDeviceStore: twoFactor?.trustedDeviceStore,
      passwordPolicy: options.passwordPolicy,
    );
    if (options.sessionStrategy == AuthSessionStrategy.session) {
      await sessionAuth.logout(ctx);
      ctx.session.destroy();
    } else {
      final signedOut = await resolveAuthSignOutForStrategy(
        strategy: AuthSessionStrategy.jwt,
        jwtCookieName: options.jwtOptions.cookieName,
        jwtCookieSecure: options.jwtOptions.secure,
        jwtCookieSameSite: options.jwtOptions.sameSite,
      );
      final expiredCookie = signedOut.expiredJwtCookie;
      if (expiredCookie != null) {
        ctx.response.cookies.add(expiredCookie);
      }
    }
    return result;
  }

  /// Reauthenticates the current user and sends an email-change confirmation.
  Future<void> requestEmailChange(
    EngineContext ctx, {
    required String newEmail,
    required String currentPassword,
    String? identifier,
  }) async {
    final session = await resolveSession(ctx);
    if (session == null) throw AuthFlowException('not_authenticated');
    final user = session.user;
    await requireAuthPasswordForUser(
      store: store,
      passwordHasher: options.passwordHasher,
      passwordPolicy: options.passwordPolicy,
      userId: user.id,
      identifier: identifier ?? user.email ?? '',
      password: currentPassword,
    );
    final issuedAt = DateTime.now().toUtc();
    final token = await issueAuthEmailChangeTokenForUser(
      store: store,
      userId: user.id,
      newEmail: newEmail,
      ttl: options.emailChangeTtl,
      now: issuedAt,
    );
    final sender = options.emailChangeSender;
    if (sender == null) throw AuthFlowException('email_change_unavailable');
    await Future.sync(
      () => sender(
        AuthEmailChangeRequest<EngineContext>(
          context: ctx,
          user: user.redacted(),
          newEmail: normalizeAuthEmail(newEmail),
          token: token,
          expiresAt: issuedAt.add(options.emailChangeTtl),
        ),
      ),
    );
  }

  /// Consumes an email-change confirmation and revokes previous sessions.
  Future<AuthUser> confirmEmailChange(
    EngineContext ctx, {
    required String token,
  }) async {
    final session = await resolveSession(ctx);
    if (session == null) throw AuthFlowException('not_authenticated');
    final updated = await confirmAuthEmailChange(
      store: store,
      userId: session.user.id,
      token: token,
    );
    final changedAt = DateTime.now().toUtc();
    await store.jwtVersions.rotate(updated.id);
    await store.sessions.revokeAllForUser(updated.id, revokedAt: changedAt);
    await sessionAuth.logout(ctx);
    if (ctx.hasSession) ctx.session.destroy();
    return updated;
  }

  /// Lists the current user's linked external identities without provider
  /// access or refresh tokens.
  Future<List<AuthAccount>> listLinkedAccounts(EngineContext ctx) async {
    final session = await resolveSession(ctx);
    if (session == null) throw AuthFlowException('not_authenticated');
    return store.accounts.listForUser(session.user.id);
  }

  /// Reauthenticates and removes one linked external identity.
  Future<void> unlinkAccount(
    EngineContext ctx, {
    required String providerId,
    required String providerAccountId,
    required String currentPassword,
  }) async {
    final session = await resolveSession(ctx);
    if (session == null) throw AuthFlowException('not_authenticated');
    final user = session.user;
    await requireAuthPasswordForUser(
      store: store,
      passwordHasher: options.passwordHasher,
      passwordPolicy: options.passwordPolicy,
      userId: user.id,
      identifier: user.email ?? '',
      password: currentPassword,
    );
    final removed = await store.accounts.unlinkForUser(
      user.id,
      providerId,
      providerAccountId,
    );
    if (!removed) throw AuthFlowException('account_not_found');
  }

  /// Reauthenticates and tombstones the current account.
  ///
  /// Plugin-owned namespaces are deleted before the core transaction.
  /// Production stores must implement the tombstone and purge operations
  /// transactionally before this operation is enabled.
  Future<void> deleteCurrentUser(
    EngineContext ctx, {
    required String currentPassword,
  }) async {
    final session = await resolveSession(ctx);
    if (session == null) throw AuthFlowException('not_authenticated');
    final user = session.user;
    await requireAuthPasswordForUser(
      store: store,
      passwordHasher: options.passwordHasher,
      passwordPolicy: options.passwordPolicy,
      userId: user.id,
      identifier: user.email ?? '',
      password: currentPassword,
    );
    final capabilities = store is AuthAdminStoreCapabilities
        ? store as AuthAdminStoreCapabilities
        : null;
    if (capabilities == null) {
      throw AuthFlowException('account_deletion_unavailable');
    }
    final contributors = runtime.registry.values
        .whereType<AuthUserDataDeletionContributor>()
        .toList(growable: false);
    for (final contributor in contributors) {
      await contributor.validateUserDeletion(user.id);
    }
    for (final contributor in contributors) {
      await contributor.deleteUserData(user.id);
    }
    await store.sessions.revokeAllForUser(user.id);
    await store.jwtVersions.rotate(user.id);
    if (!await capabilities.tombstoneUserForAdministration(user.id)) {
      throw AuthFlowException('account_deletion_failed');
    }
    await sessionAuth.logout(ctx);
    if (ctx.hasSession) ctx.session.destroy();
  }

  /// Lists active server-side sessions belonging to the current user.
  Future<List<AuthSessionInfo>> listSessions(EngineContext ctx) async {
    final current = await _requireCurrentStoredSession(ctx);
    return listAuthSessionsForUser(
      store: store,
      userId: current.userId,
      currentSessionId: current.id,
    );
  }

  /// Revokes one server-side session belonging to the current user.
  Future<void> revokeSession(EngineContext ctx, String sessionId) async {
    final current = await _requireCurrentStoredSession(ctx);
    final revoked = await Future.sync(
      () => store.sessions.revokeById(current.userId, sessionId),
    );
    if (revoked == null) {
      throw AuthFlowException('session_not_found');
    }
    if (revoked.id == current.id) {
      await sessionAuth.logout(ctx);
      ctx.session.destroy();
    }
  }

  /// Revokes every other active server-side session for the current user.
  Future<int> revokeOtherSessions(EngineContext ctx) async {
    final current = await _requireCurrentStoredSession(ctx);
    return Future.sync(
      () => store.sessions.revokeAllForUserExcept(current.userId, current.id),
    );
  }

  Future<AuthSessionRecord> _requireCurrentStoredSession(
    EngineContext ctx,
  ) async {
    if (options.sessionStrategy == AuthSessionStrategy.jwt) {
      throw AuthFlowException('session_management_unavailable');
    }
    if (!ctx.hasSession) {
      throw AuthFlowException('not_authenticated');
    }
    final current = await _resolveStoredSession(ctx);
    if (current == null) {
      throw AuthFlowException('not_authenticated');
    }
    return current;
  }

  Future<AuthResult> verifyEmail(
    EngineContext ctx,
    EmailProvider provider,
    String email,
    String token,
  ) async {
    final normalizedEmail = normalizeAuthEmail(email);
    await enforceRateLimit(
      ctx,
      provider,
      action: AuthRateLimitAction.emailCallback,
      identifier: normalizedEmail,
    );
    final stateCookieName = _emailStateCookieName(provider);
    final browserToken = _requestCookie(ctx, stateCookieName)?.value;
    final resolved = await resolveAuthEmailVerificationSignIn(
      store: store,
      email: normalizedEmail,
      token: token,
      callbackKey: options.callbackKey,
      readSession: (key) => ctx.getSession<String>(key),
      expectedBrowserToken: browserToken,
      requireBrowserToken: true,
    );
    if (resolved == null) {
      throw AuthFlowException('invalid_token');
    }
    ctx.response.cookies.add(_buildExpiredEmailStateCookie(ctx, provider));

    return _completeSignIn(
      ctx,
      resolved.user,
      redirectUrl: resolved.callbackUrl,
      provider: provider,
      isNewUser: resolved.isNewUser,
    );
  }

  Future<Uri> beginOAuth<TProfile extends Object>(
    EngineContext ctx,
    OAuthProvider<TProfile> provider, {
    String? callbackUrl,
  }) async {
    await enforceRateLimit(
      ctx,
      provider,
      action: AuthRateLimitAction.oauthStart,
    );
    final resolved =
        await resolveOAuthAuthorizationStart<EngineContext, TProfile>(
          context: ctx,
          provider: provider,
          stateKey: options.stateKey,
          pkceKey: options.pkceKey,
          nonceKey: options.nonceKey,
          callbackKey: options.callbackKey,
          challengeStore: store.oauthChallenges,
          challengeTtl: options.oauthChallengeTtl,
          callbackUrl: callbackUrl,
          writeSession: ctx.setSession,
        );
    ctx.response.cookies.add(
      _buildOAuthStateCookie(
        ctx,
        provider,
        resolved.state,
        expiresAt: DateTime.now().toUtc().add(options.oauthChallengeTtl),
      ),
    );
    return resolved.authorizationUri;
  }

  Future<AuthResult> finishOAuth<TProfile extends Object>(
    EngineContext ctx,
    OAuthProvider<TProfile> provider,
    String code,
    String? state,
  ) async {
    await enforceRateLimit(
      ctx,
      provider,
      action: AuthRateLimitAction.oauthCallback,
    );
    final stateCookieName = _oauthStateCookieName(provider);
    final browserState = _requestCookie(ctx, stateCookieName)?.value;
    final resolved =
        await resolveOAuthCallbackSignInForProvider<EngineContext, TProfile>(
          store: store,
          context: ctx,
          provider: provider,
          code: code,
          receivedState: state,
          stateKey: options.stateKey,
          pkceKey: options.pkceKey,
          nonceKey: options.nonceKey,
          callbackKey: options.callbackKey,
          readSession: (key) => ctx.getSession<String>(key),
          removeSession: ctx.removeSession,
          consumeChallenge: store.oauthChallenges.consume,
          expectedBrowserState: browserState,
          requireBrowserState: true,
          httpClient: httpClient,
          fallbackAccountId: secureRandomToken,
        );
    ctx.response.cookies.add(_buildExpiredOAuthStateCookie(ctx, provider));
    final signIn = resolved.signIn;
    final resolvedUser = signIn.user;
    final isNewUser = signIn.isNewUser;
    if (signIn.userUpdated) {
      await _emitAuthEvent(
        ctx,
        AuthUpdateUserEvent(
          context: ctx,
          user: resolvedUser,
          provider: provider,
        ),
      );
    }

    final account = signIn.account;
    final profileMap = signIn.profile;
    await _emitAuthEvent(
      ctx,
      AuthLinkAccountEvent(
        context: ctx,
        account: account,
        user: resolvedUser,
        provider: provider,
        profile: profileMap,
      ),
    );

    final redirectUrl = resolved.callbackUrl;
    return _completeSignIn(
      ctx,
      resolvedUser,
      redirectUrl: redirectUrl,
      provider: provider,
      account: account,
      profile: profileMap,
      isNewUser: isNewUser,
    );
  }

  /// Completes authentication for a custom callback provider.
  ///
  /// This method is used by [AuthRoutes] to handle providers that implement
  /// the [CallbackProvider] mixin (e.g., Telegram).
  ///
  /// [ctx] is the engine context.
  /// [provider] is the custom callback provider.
  /// [user] is the authenticated user.
  /// [redirectUrl] is an optional redirect URL after sign-in.
  Future<AuthResult> completeCustomCallback(
    EngineContext ctx,
    AuthProvider provider,
    AuthUser user, {
    String? redirectUrl,
    Map<String, dynamic>? profile,
  }) async {
    return _completeSignIn(
      ctx,
      user,
      redirectUrl: redirectUrl,
      provider: provider,
      account: AuthAccount(providerId: provider.id, providerAccountId: user.id),
      profile: profile,
      isNewUser: false,
    );
  }

  /// Updates the current auth session with the given [principal].
  ///
  /// This method replaces the authenticated identity stored in the current
  /// request context. Use it after changing user attributes, roles, or other
  /// profile data that should be reflected in the session immediately.
  ///
  /// **Session strategy:** replaces the session principal via
  /// [SessionAuthService.login] and resets the session issued-at timestamp.
  ///
  /// **JWT strategy:** builds new claims from the principal, invokes the
  /// configured JWT callback (if any), issues a fresh token, and attaches
  /// it as an HTTP-only cookie.
  ///
  /// Returns an [AuthSession] reflecting the updated state.
  ///
  /// Throws [AuthFlowException] with code `missing_jwt_secret` when using
  /// the JWT strategy and no secret is configured.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Preferred: use the SessionAuth convenience method which delegates
  /// // to this automatically:
  /// await SessionAuth.updateSession(ctx, updatedPrincipal);
  ///
  /// // Or call directly when you need the returned AuthSession:
  /// final manager = ctx.container.get<AuthManager>();
  /// final session = await manager.updateSession(ctx, updated);
  /// ```
  Future<AuthSession> updateSession(
    EngineContext ctx,
    AuthPrincipal principal,
  ) async {
    final resolved =
        await resolveAuthSessionUpdateForStrategyWithCallbacks<EngineContext>(
          strategy: options.sessionStrategy,
          callbacks: callbacks,
          context: ctx,
          principal: principal,
          jwtOptions: options.jwtOptions,
          protectedJwtClaims: options.sessionStrategy == AuthSessionStrategy.jwt
              ? await _jwtVersionClaims(AuthUser.fromPrincipal(principal))
              : null,
          applySessionMaxAge: () => _applySessionMaxAge(ctx),
          persistSessionPrincipal: (nextPrincipal) =>
              sessionAuth.update(ctx, nextPrincipal),
          writeSessionIssuedAt: (issuedAtUtc) =>
              _setSessionIssuedAt(ctx, issuedAtUtc),
          resolveSessionExpiry: () => _sessionExpiry(ctx),
        );
    final jwtCookie = resolved.jwtCookie;
    if (jwtCookie != null) {
      ctx.response.cookies.add(jwtCookie);
    }
    return resolved.session;
  }

  Future<AuthSession?> resolveSession(EngineContext ctx) async {
    final storedSession = await _resolveStoredSession(ctx);
    if (options.sessionStrategy == AuthSessionStrategy.session &&
        ctx.hasSession &&
        storedSession == null) {
      return null;
    }
    final resolved =
        await resolveAuthSessionForStrategyWithCallbacks<EngineContext>(
          strategy: options.sessionStrategy,
          callbacks: callbacks,
          context: ctx,
          jwtOptions: options.jwtOptions,
          sessionUpdateAge: options.sessionUpdateAge,
          readSessionPrincipal: () => sessionAuth.current(ctx),
          applySessionMaxAge: () => _applySessionMaxAge(ctx),
          readSessionIssuedAt: () =>
              ctx.getSession<String>(authSessionIssuedAtKey),
          writeSessionIssuedAt: (issuedAtUtc) =>
              _setSessionIssuedAt(ctx, issuedAtUtc),
          touchSession: ctx.session.touch,
          resolveSessionExpiry: () => _sessionExpiry(ctx),
          readJwtToken: () => _resolveJwtToken(ctx),
          validateJwtClaims: _validateJwtClaims,
          httpClient: httpClient,
        );
    final refreshCookie = resolved.refreshCookie;
    if (refreshCookie != null) {
      ctx.response.cookies.add(refreshCookie);
    }
    if (storedSession != null &&
        resolved.session != null &&
        storedSession.userId != resolved.session!.user.id) {
      return null;
    }
    final session = resolved.session;
    if (session != null) {
      await _enforceAuthenticationPolicy(
        ctx,
        session.user,
        AuthAuthenticationPolicyPhase.resolveSession,
      );
    }
    return session;
  }

  Future<void> _enforceAuthenticationPolicy(
    EngineContext ctx,
    AuthUser user,
    AuthAuthenticationPolicyPhase phase,
  ) async {
    if (authUserIsDisabled(user)) {
      throw AuthFlowException('account_unavailable');
    }
    if (options.requireVerifiedEmail && !authUserEmailIsVerified(user)) {
      throw AuthFlowException('email_verification_required');
    }
    await runtime.registry.enforceAuthenticationPolicy(
      AuthAuthenticationPolicyRequest(context: ctx, user: user, phase: phase),
    );
  }

  /// Replaces the current server-session identity for a portable plugin.
  Future<AuthSession> replacePluginSession(
    EngineContext ctx,
    AuthUser user, {
    required String authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  }) async {
    if (options.sessionStrategy != AuthSessionStrategy.session) {
      throw AuthFlowException('impersonation_requires_server_session');
    }
    if (ctx.hasSession) {
      await store.sessions.revoke(hashOpaqueToken(ctx.sessionId));
    }
    final result = await _completeSignIn(
      ctx,
      user,
      authenticationMethod: authenticationMethod,
      maximumAge: maximumAge,
      impersonatedBy: impersonatedBy,
    );
    return result.session;
  }

  Future<String?> currentStoredSessionId(EngineContext ctx) async =>
      (await _resolveStoredSession(ctx))?.id;

  Future<void> signOutPluginSession(EngineContext ctx) async {
    await logout(ctx);
    if (ctx.hasSession) ctx.session.destroy();
  }

  /// Revokes the persisted server-side session before clearing framework
  /// session state.
  Future<void> logout(EngineContext ctx) async {
    if (options.sessionStrategy == AuthSessionStrategy.session &&
        ctx.hasSession) {
      await store.sessions.revoke(hashOpaqueToken(ctx.sessionId));
    }
    await sessionAuth.logout(ctx);
  }

  Future<String?> resolveRedirect(
    EngineContext ctx,
    String? url, {
    AuthProvider? provider,
  }) async {
    return resolveAuthRedirectWithCallbacks<EngineContext>(
      callbacks: callbacks,
      context: ctx,
      url: url,
      baseUrl: baseUrlFromUri(
        ctx.requestedUri,
        defaultScheme: ctx.scheme,
        defaultHost: ctx.host,
      ),
      provider: provider,
    );
  }

  Future<Map<String, dynamic>> buildSessionPayload(
    EngineContext ctx,
    AuthSession session, {
    AuthProvider? provider,
  }) async {
    final finalPayload =
        await resolveAuthSessionPayloadWithCallbacks<EngineContext>(
          callbacks: callbacks,
          context: ctx,
          session: session,
          strategy: session.strategy ?? options.sessionStrategy,
          provider: provider,
          payload: session.toJson(
            includeToken: options.exposeJwtTokenInSessionResponse,
          ),
        );
    await _emitAuthEvent(
      ctx,
      AuthSessionEvent(
        context: ctx,
        session: session,
        payload: finalPayload,
        strategy: session.strategy ?? options.sessionStrategy,
        provider: provider,
      ),
    );
    return finalPayload;
  }

  Future<void> emitSignOut(EngineContext ctx, {AuthSession? session}) async {
    await _emitAuthEvent(
      ctx,
      AuthSignOutEvent(
        context: ctx,
        strategy: session?.strategy ?? options.sessionStrategy,
        session: session,
        user: session?.user,
      ),
    );
  }

  Future<void> _emitAuthEvent<T extends Event>(
    EngineContext ctx,
    T event,
  ) async {
    final container = ctx.container;
    if (!container.has<EventManager>()) {
      return;
    }
    final manager = await container.make<EventManager>();
    manager.publish(event);
  }

  Future<AuthResult> _completeSignIn(
    EngineContext ctx,
    AuthUser user, {
    String? redirectUrl,
    AuthProvider? provider,
    AuthAccount? account,
    Map<String, dynamic>? profile,
    AuthCredentials? credentials,
    bool isNewUser = false,
    String? authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  }) async {
    if (user.id.trim().isEmpty) {
      throw AuthFlowException('user_resolution_failed');
    }
    final anonymous = this.anonymous;
    final principal = SessionAuth.current(ctx);
    if (anonymous != null &&
        principal != null &&
        principal.id != user.id &&
        principal.attributes['isAnonymous'] == true) {
      final anonymousUser = await store.users.findById(principal.id);
      if (anonymousUser?.isAnonymous == true) {
        await anonymous.linkAnonymousAccount(
          context: ctx,
          anonymousUser: anonymousUser!,
          newUser: user,
        );
      }
    }
    await _enforceAuthenticationPolicy(
      ctx,
      user,
      AuthAuthenticationPolicyPhase.beforeSessionIssue,
    );
    final resolvedRedirect =
        await resolveAuthSignInRedirectTarget<EngineContext>(
          callbacks: callbacks,
          context: ctx,
          user: user,
          strategy: options.sessionStrategy,
          provider: provider,
          account: account,
          profile: profile,
          credentials: credentials,
          isNewUser: isNewUser,
          callbackUrl: redirectUrl,
          resolveRedirect: (candidate) =>
              resolveRedirect(ctx, candidate, provider: provider),
        );

    if (isNewUser) {
      await _emitAuthEvent(
        ctx,
        AuthCreateUserEvent(
          context: ctx,
          user: user,
          provider: provider,
          profile: profile,
        ),
      );
    }

    DateTime? sessionExpiresAt;
    if (options.sessionStrategy == AuthSessionStrategy.session) {
      _applySessionMaxAge(ctx);
      if (maximumAge != null) {
        ctx.session.options.setMaxAge(maximumAge.inSeconds);
      }
      await sessionAuth.login(ctx, user.toPrincipal());
      _setSessionIssuedAt(ctx, DateTime.now().toUtc());
      sessionExpiresAt = _sessionExpiry(ctx);
      await _persistStoredSession(
        ctx,
        user: user,
        provider: provider,
        credentials: credentials,
        expiresAt: sessionExpiresAt,
        authenticationMethod: authenticationMethod,
        impersonatedBy: impersonatedBy,
      );
    }

    final resolvedSignIn =
        await resolveAuthSignInResultForStrategyWithCallbacks<EngineContext>(
          callbacks: callbacks,
          context: ctx,
          strategy: options.sessionStrategy,
          user: user,
          redirectUrl: resolvedRedirect,
          jwtOptions: options.jwtOptions,
          sessionExpiresAt: sessionExpiresAt,
          protectedClaims: options.sessionStrategy == AuthSessionStrategy.jwt
              ? await _jwtVersionClaims(user)
              : null,
          provider: provider,
          account: account,
          profile: profile,
          isNewUser: isNewUser,
        );

    final issuedJwt = resolvedSignIn.issuedJwt;
    if (issuedJwt != null) {
      ctx.response.cookies.add(issuedJwt.cookie);
    }

    final result = resolvedSignIn.result;
    final session = result.session;
    await _emitAuthEvent(
      ctx,
      AuthSignInEvent(
        context: ctx,
        user: user,
        session: session,
        strategy: options.sessionStrategy,
        provider: provider,
        account: account,
        profile: profile,
        credentials: credentials,
        redirectUrl: resolvedRedirect,
        isNewUser: isNewUser,
      ),
    );
    return result;
  }

  void _applySessionMaxAge(EngineContext ctx) {
    final maxAgeSeconds = resolveAuthSessionMaxAgeSeconds(
      options.sessionMaxAge,
    );
    if (maxAgeSeconds == null) {
      return;
    }
    ctx.session.options.setMaxAge(maxAgeSeconds);
  }

  void _setSessionIssuedAt(EngineContext ctx, DateTime issuedAt) {
    ctx.setSession(
      authSessionIssuedAtKey,
      serializeAuthSessionIssuedAt(issuedAt),
    );
  }

  DateTime? _sessionExpiry(EngineContext ctx) {
    return resolveAuthSessionExpiry(
      sessionMaxAge: options.sessionMaxAge,
      sessionOptionsMaxAgeSeconds: ctx.session.options.maxAge,
    );
  }

  Future<Map<String, dynamic>> _jwtVersionClaims(AuthUser user) async {
    return <String, dynamic>{
      authJwtVersionClaim: await store.jwtVersions.current(user.id),
    };
  }

  Future<bool> _validateJwtClaims(
    Map<String, dynamic> claims,
    AuthUser user,
  ) async {
    final rawVersion = claims[authJwtVersionClaim];
    final version = switch (rawVersion) {
      int value when value >= 0 => value,
      num value when value.isFinite && value == value.toInt() && value >= 0 =>
        value.toInt(),
      _ => null,
    };
    if (version == null || user.id.trim().isEmpty) {
      return false;
    }
    return version == await store.jwtVersions.current(user.id);
  }

  String? _resolveJwtToken(EngineContext ctx) {
    return resolveBearerOrCookieToken(
      authorizationHeader: ctx.request.headers.value(options.jwtOptions.header),
      bearerPrefix: options.jwtOptions.bearerPrefix,
      cookieName: options.jwtOptions.cookieName,
      cookies: ctx.request.cookies.map(
        (cookie) => MapEntry<String, String>(cookie.name, cookie.value),
      ),
    );
  }

  Future<AuthSessionRecord?> _resolveStoredSession(EngineContext ctx) async {
    if (!ctx.hasSession) {
      return null;
    }
    final tokenHash = hashOpaqueToken(ctx.sessionId);
    final record = await store.sessions.find(tokenHash);
    if (record == null || !record.isActive()) {
      return null;
    }
    return await store.sessions.touch(tokenHash, DateTime.now().toUtc());
  }

  /// Enforces the configured limiter for an adapter-specific auth boundary.
  ///
  /// Routed uses this before invoking a custom callback provider, because the
  /// provider callback itself may perform expensive or externally visible
  /// work. Built-in auth methods call this internally.
  Future<void> enforceRateLimit(
    EngineContext ctx,
    AuthProvider provider, {
    required AuthRateLimitAction action,
    String? identifier,
  }) {
    return enforceRateLimitForProviderId(
      ctx,
      provider.id,
      action: action,
      identifier: identifier,
    );
  }

  /// Enforces a limiter for a boundary without a configured auth provider.
  Future<void> enforceRateLimitForProviderId(
    EngineContext ctx,
    String providerId, {
    required AuthRateLimitAction action,
    String? identifier,
  }) {
    return enforceAuthRateLimit<EngineContext>(
      limiter: options.rateLimiter,
      request: AuthRateLimitRequest<EngineContext>.operation(
        operation: AuthRateLimitOperation.core(action),
        providerId: providerId,
        context: ctx,
        identifier: identifier?.trim(),
      ),
    );
  }

  /// Enforces a namespaced plugin rate-limit operation.
  Future<void> enforceRateLimitOperation(
    EngineContext ctx, {
    required AuthRateLimitOperation operation,
    String providerId = 'organization',
    String? identifier,
  }) {
    return enforceAuthRateLimit<EngineContext>(
      limiter: options.rateLimiter,
      request: AuthRateLimitRequest<EngineContext>.operation(
        operation: operation,
        providerId: providerId,
        context: ctx,
        identifier: identifier?.trim(),
      ),
    );
  }

  Cookie? _requestCookie(EngineContext ctx, String name) {
    for (final cookie in ctx.request.cookies) {
      if (cookie.name == name) return cookie;
    }
    return null;
  }

  String _twoFactorSessionBinding(EngineContext ctx) {
    final rawBinding = options.sessionStrategy == AuthSessionStrategy.jwt
        ? _resolveJwtToken(ctx)
        : ctx.sessionId;
    if (rawBinding == null || rawBinding.trim().isEmpty) {
      throw AuthFlowException('unauthorized');
    }
    return hashOpaqueToken(rawBinding);
  }

  bool _isHttps(EngineContext ctx) => ctx.scheme.toLowerCase() == 'https';

  String _oauthStateCookieName(AuthProvider provider) {
    return 'routed_oauth_state_${hashOpaqueToken(provider.id).substring(0, 16)}';
  }

  String _emailStateCookieName(EmailProvider provider) {
    return 'routed_email_state_${hashOpaqueToken(provider.id).substring(0, 16)}';
  }

  Cookie _buildEmailStateCookie(
    EngineContext ctx,
    EmailProvider provider,
    String token, {
    required DateTime expiresAt,
  }) {
    final secure = ctx.scheme.toLowerCase() == 'https';
    return Cookie(_emailStateCookieName(provider), token)
      ..httpOnly = true
      ..expires = expiresAt
      ..path = _oauthCookiePath()
      ..secure = secure
      ..sameSite = secure ? SameSite.none : SameSite.lax;
  }

  Cookie _buildExpiredEmailStateCookie(
    EngineContext ctx,
    EmailProvider provider,
  ) {
    final cookie = _buildEmailStateCookie(
      ctx,
      provider,
      '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    cookie.maxAge = 0;
    return cookie;
  }

  Cookie _buildOAuthStateCookie(
    EngineContext ctx,
    AuthProvider provider,
    String state, {
    required DateTime expiresAt,
  }) {
    final secure = ctx.scheme.toLowerCase() == 'https';
    return Cookie(_oauthStateCookieName(provider), state)
      ..httpOnly = true
      ..expires = expiresAt
      ..path = _oauthCookiePath()
      ..secure = secure
      ..sameSite = secure ? SameSite.none : SameSite.lax;
  }

  Cookie _buildExpiredOAuthStateCookie(
    EngineContext ctx,
    AuthProvider provider,
  ) {
    final cookie = _buildOAuthStateCookie(
      ctx,
      provider,
      '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    cookie.maxAge = 0;
    return cookie;
  }

  String _oauthCookiePath() {
    final path = options.basePath.trim();
    if (path.isEmpty || path == '/') return '/';
    return path.startsWith('/') ? path : '/$path';
  }

  Future<void> _persistStoredSession(
    EngineContext ctx, {
    required AuthUser user,
    required AuthProvider? provider,
    required AuthCredentials? credentials,
    required DateTime? expiresAt,
    String? authenticationMethod,
    String? impersonatedBy,
  }) async {
    if (!ctx.hasSession) {
      return;
    }
    final now = DateTime.now().toUtc();
    final sessionId = ctx.sessionId;
    final tokenHash = hashOpaqueToken(sessionId);
    final record = AuthSessionRecord(
      id: secureRandomToken(length: 16),
      tokenHash: tokenHash,
      userId: user.id,
      createdAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
      lastUsedAt: now,
      ipAddress: ctx.request.clientIP,
      userAgent: ctx.request.headers.value(HttpHeaders.userAgentHeader),
      authenticationMethod:
          authenticationMethod ??
          provider?.id ??
          (credentials == null ? 'unknown' : 'credentials'),
      impersonatedBy: impersonatedBy,
    );
    final previousId = ctx.session.previousId;
    if (previousId != null) {
      final rotated = await store.sessions.rotate(
        previousTokenHash: hashOpaqueToken(previousId),
        replacement: record,
      );
      if (rotated != null) {
        return;
      }
    }
    await store.sessions.create(record);
  }
}
