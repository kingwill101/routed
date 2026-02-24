import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show
        AuthAccount,
        AuthAdapter,
        AuthCallbacks,
        AuthCredentials,
        AuthEmailVerificationPayload,
        AuthJwtCallbackContext,
        authorizeCredentialsRegistration,
        authorizeCredentialsSignIn,
        resolveAuthJwtClaims,
        resolveAuthRedirectTarget,
        resolveAuthSessionPayload,
        resolveAuthSignInDecision,
        AuthPrincipal,
        AuthProvider,
        authEmailCallbackSessionKey,
        authProviderCallbackSessionKey,
        authProviderPkceSessionKey,
        authProviderStateSessionKey,
        authProviderSummaries,
        baseUrlFromUri,
        buildOAuthAuthAccount,
        buildOAuthAuthorizationParameters,
        ensureOAuthStateMatches,
        exchangeOAuthAuthorizationCode,
        resolveAuthProviderById,
        AuthRedirectCallbackContext,
        AuthResult,
        AuthSessionCallbackContext,
        AuthSession,
        AuthSessionStrategy,
        AuthSignInCallbackContext,
        AuthFlowException,
        AuthUser,
        AuthVerificationTokenStore,
        InMemoryAuthVerificationTokenStore,
        authJwtClaimsForUser,
        authUserFromJwtClaims,
        resolveAuthAccountId,
        AuthOAuthUserResolution,
        AuthEmailUserResolution,
        consumeAuthVerificationToken,
        clearAuthVerificationTokens,
        persistAuthVerificationToken,
        prepareAuthEmailVerificationPayload,
        resolveAuthUserByEmailOrCreate,
        resolveOAuthUserForAccount,
        resolveBearerOrCookieToken,
        resolveCsrfToken,
        validateCsrfToken,
        CallbackProvider,
        CredentialsProvider,
        EmailProvider,
        buildJwtTokenCookie,
        JwtAuthException,
        jwtIssuedAtUtc,
        JwtIssuer,
        JwtPayload,
        JwtVerifier,
        OAuthProvider,
        loadOAuthProfile,
        oauthTokenExpiryFromSeconds,
        pkceS256CodeChallenge,
        authSessionIssuedAtKey,
        authSessionRefreshAction,
        AuthSessionRefreshAction,
        resolveAuthSessionExpiry,
        serializeAuthSessionIssuedAt,
        secureRandomToken,
        shouldRefreshJwtByIssuedAt;
import 'package:routed/src/auth/hooks.dart';
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/events/event.dart';
import 'package:routed/src/events/event_manager.dart';

import 'auth_options.dart';

/// {@macro routed_auth_manager}
class AuthManager {
  AuthManager(this.options)
    : _tokenStore = options.tokenStore ?? InMemoryAuthVerificationTokenStore(),
      _httpClient = options.httpClient;

  final AuthOptions options;
  final AuthVerificationTokenStore _tokenStore;
  http.Client? _httpClient;

  AuthAdapter get adapter => options.adapter;

  SessionAuthService get sessionAuth =>
      options.sessionAuth ?? SessionAuth.instance;

  http.Client get httpClient => _httpClient ??= http.Client();

  AuthCallbacks<EngineContext> get callbacks => options.callbacks;

  AuthProvider? resolveProvider(String id) =>
      resolveAuthProviderById(options.providers, id);

  List<Map<String, dynamic>> providerSummaries() =>
      authProviderSummaries(options.providers);

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

  Future<AuthResult> signInWithCredentials(
    EngineContext ctx,
    CredentialsProvider provider,
    AuthCredentials credentials,
  ) async {
    final user = await authorizeCredentialsSignIn(
      adapter: adapter,
      provider: provider,
      context: ctx,
      credentials: credentials,
    );

    if (user == null) {
      throw AuthFlowException('invalid_credentials');
    }

    return _completeSignIn(
      ctx,
      user,
      provider: provider,
      credentials: credentials,
    );
  }

  Future<AuthResult> registerWithCredentials(
    EngineContext ctx,
    CredentialsProvider provider,
    AuthCredentials credentials,
  ) async {
    final user = await authorizeCredentialsRegistration(
      adapter: adapter,
      provider: provider,
      context: ctx,
      credentials: credentials,
    );

    if (user == null) {
      throw AuthFlowException('registration_failed');
    }

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
    await clearAuthVerificationTokens(
      adapter: adapter,
      tokenStore: _tokenStore,
      identifier: email,
    );
    final AuthEmailVerificationPayload payload =
        prepareAuthEmailVerificationPayload(
          provider: provider,
          email: email,
          callbackUrl: callbackUrl,
          sessionStrategy: options.sessionStrategy,
          generateToken: secureRandomToken,
        );
    if (callbackUrl.isNotEmpty) {
      ctx.setSession(
        authEmailCallbackSessionKey(options.callbackKey),
        callbackUrl,
      );
    }
    await persistAuthVerificationToken(
      adapter: adapter,
      tokenStore: _tokenStore,
      verification: payload.verification,
    );
    await Future.sync(
      () => provider.sendVerificationRequest(ctx, provider, payload.request),
    );
    return payload.pendingResult;
  }

  Future<AuthResult> verifyEmail(
    EngineContext ctx,
    EmailProvider provider,
    String email,
    String token,
  ) async {
    final resolved = await consumeAuthVerificationToken(
      adapter: adapter,
      tokenStore: _tokenStore,
      identifier: email,
      token: token,
    );
    if (resolved == null) {
      throw AuthFlowException('invalid_token');
    }

    final AuthEmailUserResolution userResolution =
        await resolveAuthUserByEmailOrCreate(adapter: adapter, email: email);
    final user = userResolution.user;
    final isNewUser = userResolution.isNewUser;
    final redirectUrl = ctx.getSession<String>(
      authEmailCallbackSessionKey(options.callbackKey),
    );

    return _completeSignIn(
      ctx,
      user,
      redirectUrl: redirectUrl,
      provider: provider,
      isNewUser: isNewUser,
    );
  }

  Future<Uri> beginOAuth<TProfile extends Object>(
    EngineContext ctx,
    OAuthProvider<TProfile> provider, {
    String? callbackUrl,
  }) async {
    final state = secureRandomToken();
    ctx.setSession(
      authProviderStateSessionKey(options.stateKey, provider.id),
      state,
    );

    if (provider.onStateGenerated != null) {
      await Future.sync(() => provider.onStateGenerated!(ctx, provider, state));
    }

    String? verifier;
    String? challenge;
    if (provider.usePkce) {
      verifier = secureRandomToken(length: 48);
      challenge = pkceS256CodeChallenge(verifier);
      ctx.setSession(
        authProviderPkceSessionKey(options.pkceKey, provider.id),
        verifier,
      );
    }
    final params = buildOAuthAuthorizationParameters(
      provider,
      state: state,
      codeChallenge: challenge,
      callbackUrl: callbackUrl,
    );

    if (callbackUrl != null && callbackUrl.isNotEmpty) {
      ctx.setSession(
        authProviderCallbackSessionKey(options.callbackKey, provider.id),
        callbackUrl,
      );
    }

    return provider.authorizationEndpoint.replace(queryParameters: params);
  }

  Future<AuthResult> finishOAuth<TProfile extends Object>(
    EngineContext ctx,
    OAuthProvider<TProfile> provider,
    String code,
    String? state,
  ) async {
    final expectedState = ctx.getSession<String>(
      authProviderStateSessionKey(options.stateKey, provider.id),
    );
    ensureOAuthStateMatches(expectedState: expectedState, receivedState: state);

    final verifier = ctx.getSession<String>(
      authProviderPkceSessionKey(options.pkceKey, provider.id),
    );
    final tokenResponse = await exchangeOAuthAuthorizationCode(
      provider,
      code: code,
      codeVerifier: verifier,
      httpClient: httpClient,
    );

    final rawProfile = await loadOAuthProfile(
      provider,
      token: tokenResponse,
      httpClient: httpClient,
    );
    final parsedProfile = provider.parseProfile(rawProfile);
    final enrichedProfile = await Future.sync(
      () =>
          provider.enrichProfile(ctx, tokenResponse, httpClient, parsedProfile),
    );
    final mapped = provider.mapProfile(enrichedProfile);
    final override = await Future.sync(
      () => provider.overrideProfile(ctx, enrichedProfile),
    );
    final user = override ?? mapped;

    final profileMap = provider.serializeProfile(enrichedProfile);
    final accountId = resolveAuthAccountId(
      profileMap,
      user,
      fallbackId: secureRandomToken,
    );
    final accountExpiresAt = oauthTokenExpiryFromSeconds(
      tokenResponse.expiresIn,
    );

    final AuthOAuthUserResolution userResolution =
        await resolveOAuthUserForAccount(
          adapter: adapter,
          providerId: provider.id,
          accountId: accountId,
          mappedUser: user,
        );
    final resolvedUser = userResolution.user;
    final isNewUser = userResolution.isNewUser;
    if (userResolution.userUpdated) {
      await _emitAuthEvent(
        ctx,
        AuthUpdateUserEvent(
          context: ctx,
          user: resolvedUser,
          provider: provider,
        ),
      );
    }

    final account = buildOAuthAuthAccount(
      providerId: provider.id,
      providerAccountId: accountId,
      userId: resolvedUser.id,
      token: tokenResponse,
      expiresAt: accountExpiresAt,
      metadata: profileMap,
    );

    await Future.sync(() => adapter.linkAccount(account));
    await _emitAuthEvent(
      ctx,
      AuthLinkAccountEvent(
        context: ctx,
        account: account,
        user: resolvedUser,
        profile: profileMap,
      ),
    );

    final redirectUrl = ctx.getSession<String>(
      authProviderCallbackSessionKey(options.callbackKey, provider.id),
    );
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
    final user = AuthUser.fromPrincipal(principal);
    switch (options.sessionStrategy) {
      case AuthSessionStrategy.session:
        _applySessionMaxAge(ctx);
        await sessionAuth.login(ctx, principal);
        _setSessionIssuedAt(ctx, DateTime.now().toUtc());
        final expires = _sessionExpiry(ctx);
        return AuthSession(
          user: user,
          expiresAt: expires,
          strategy: AuthSessionStrategy.session,
        );
      case AuthSessionStrategy.jwt:
        if (options.jwtOptions.secret.isEmpty) {
          throw AuthFlowException('missing_jwt_secret');
        }
        final issuer = _jwtIssuer();
        final claims = await _applyJwtCallback(
          AuthJwtCallbackContext<EngineContext>(
            context: ctx,
            token: authJwtClaimsForUser(user),
            user: user,
            strategy: AuthSessionStrategy.jwt,
          ),
        );
        final token = issuer.issue(claims);
        ctx.response.cookies.add(
          buildJwtTokenCookie(
            options.jwtOptions.cookieName,
            token,
            expires: issuer.expiry,
          ),
        );
        return AuthSession(
          user: user,
          expiresAt: issuer.expiry,
          strategy: AuthSessionStrategy.jwt,
          token: token,
        );
    }
  }

  Future<AuthSession?> resolveSession(EngineContext ctx) async {
    switch (options.sessionStrategy) {
      case AuthSessionStrategy.session:
        final principal = sessionAuth.current(ctx);
        if (principal == null) return null;
        _applySessionMaxAge(ctx);
        _refreshSessionIfNeeded(ctx);
        final user = AuthUser.fromPrincipal(principal);
        final expires = _sessionExpiry(ctx);
        return AuthSession(
          user: user,
          expiresAt: expires,
          strategy: AuthSessionStrategy.session,
        );
      case AuthSessionStrategy.jwt:
        final token = _resolveJwtToken(ctx);
        if (token == null || token.isEmpty) return null;
        if (options.jwtOptions.secret.isEmpty) return null;
        final verifier = _jwtVerifier();
        JwtPayload payload;
        try {
          payload = await verifier.verifyToken(token);
        } on JwtAuthException {
          return null;
        }
        final user = authUserFromJwtClaims(payload.claims);
        var resolvedToken = token;
        var resolvedExpiry = payload.token.claims.expiry?.toUtc();
        final refreshed = await _refreshJwtIfNeeded(ctx, payload, user);
        if (refreshed != null) {
          resolvedToken = refreshed.token;
          resolvedExpiry = refreshed.expiresAt;
        }
        return AuthSession(
          user: user,
          expiresAt: resolvedExpiry,
          strategy: AuthSessionStrategy.jwt,
          token: resolvedToken,
        );
    }
  }

  Future<Map<String, dynamic>> _applyJwtCallback(
    AuthJwtCallbackContext<EngineContext> context,
  ) async {
    return resolveAuthJwtClaims<EngineContext>(
      callback: callbacks.jwt,
      context: context,
    );
  }

  Future<String?> resolveRedirect(
    EngineContext ctx,
    String? url, {
    AuthProvider? provider,
  }) async {
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    final resolved = await resolveAuthRedirectTarget<EngineContext>(
      callback: callbacks.redirect,
      context: AuthRedirectCallbackContext<EngineContext>(
        context: ctx,
        url: url,
        baseUrl: baseUrlFromUri(ctx.request.uri),
        provider: provider,
      ),
    );
    return resolved ?? url;
  }

  Future<Map<String, dynamic>> buildSessionPayload(
    EngineContext ctx,
    AuthSession session, {
    AuthProvider? provider,
  }) async {
    final payload = Map<String, dynamic>.from(session.toJson());
    final finalPayload = await resolveAuthSessionPayload<EngineContext>(
      callback: callbacks.session,
      context: AuthSessionCallbackContext<EngineContext>(
        context: ctx,
        session: session,
        payload: payload,
        user: session.user,
        strategy: session.strategy ?? options.sessionStrategy,
        provider: provider,
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
  }) async {
    final decision = await resolveAuthSignInDecision<EngineContext>(
      callback: callbacks.signIn,
      context: AuthSignInCallbackContext<EngineContext>(
        context: ctx,
        user: user,
        strategy: options.sessionStrategy,
        provider: provider,
        account: account,
        profile: profile,
        credentials: credentials,
        isNewUser: isNewUser,
        callbackUrl: redirectUrl,
      ),
    );

    if (!decision.allowed) {
      throw AuthFlowException('sign_in_blocked');
    }

    final resolvedRedirect = await resolveRedirect(
      ctx,
      decision.redirectUrl ?? redirectUrl,
      provider: provider,
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

    switch (options.sessionStrategy) {
      case AuthSessionStrategy.session:
        _applySessionMaxAge(ctx);
        await sessionAuth.login(ctx, user.toPrincipal());
        _setSessionIssuedAt(ctx, DateTime.now().toUtc());
        final expires = _sessionExpiry(ctx);
        final session = AuthSession(
          user: user,
          expiresAt: expires,
          strategy: AuthSessionStrategy.session,
        );
        await _emitAuthEvent(
          ctx,
          AuthSignInEvent(
            context: ctx,
            user: user,
            session: session,
            strategy: AuthSessionStrategy.session,
            provider: provider,
            account: account,
            profile: profile,
            credentials: credentials,
            redirectUrl: resolvedRedirect,
            isNewUser: isNewUser,
          ),
        );
        return AuthResult(
          user: user,
          session: session,
          redirectUrl: resolvedRedirect,
        );
      case AuthSessionStrategy.jwt:
        if (options.jwtOptions.secret.isEmpty) {
          throw AuthFlowException('missing_jwt_secret');
        }
        final issuer = _jwtIssuer();
        final claims = await _applyJwtCallback(
          AuthJwtCallbackContext<EngineContext>(
            context: ctx,
            token: authJwtClaimsForUser(user),
            user: user,
            strategy: AuthSessionStrategy.jwt,
            provider: provider,
            account: account,
            profile: profile,
            isNewUser: isNewUser,
          ),
        );
        final token = issuer.issue(claims);
        ctx.response.cookies.add(
          buildJwtTokenCookie(
            options.jwtOptions.cookieName,
            token,
            expires: issuer.expiry,
          ),
        );
        final session = AuthSession(
          user: user,
          expiresAt: issuer.expiry,
          strategy: AuthSessionStrategy.jwt,
          token: token,
        );
        await _emitAuthEvent(
          ctx,
          AuthSignInEvent(
            context: ctx,
            user: user,
            session: session,
            strategy: AuthSessionStrategy.jwt,
            provider: provider,
            account: account,
            profile: profile,
            credentials: credentials,
            redirectUrl: resolvedRedirect,
            isNewUser: isNewUser,
          ),
        );
        return AuthResult(
          user: user,
          session: session,
          redirectUrl: resolvedRedirect,
        );
    }
  }

  JwtIssuer _jwtIssuer() => JwtIssuer(options.jwtOptions);

  JwtVerifier _jwtVerifier() {
    return JwtVerifier(
      options: options.jwtOptions.toVerifierOptions(),
      httpClient: httpClient,
    );
  }

  void _applySessionMaxAge(EngineContext ctx) {
    final maxAge = options.sessionMaxAge;
    if (maxAge == null) {
      return;
    }
    ctx.session.options.setMaxAge(maxAge.inSeconds);
  }

  void _setSessionIssuedAt(EngineContext ctx, DateTime issuedAt) {
    ctx.setSession(
      authSessionIssuedAtKey,
      serializeAuthSessionIssuedAt(issuedAt),
    );
  }

  void _refreshSessionIfNeeded(EngineContext ctx) {
    final updateAge = options.sessionUpdateAge;
    if (updateAge == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final action = authSessionRefreshAction(
      issuedAtValue: ctx.getSession<String>(authSessionIssuedAtKey),
      updateAge: updateAge,
      now: now,
    );
    switch (action) {
      case AuthSessionRefreshAction.initialize:
        _setSessionIssuedAt(ctx, now);
        return;
      case AuthSessionRefreshAction.refresh:
        _setSessionIssuedAt(ctx, now);
        ctx.session.touch();
        return;
      case AuthSessionRefreshAction.keep:
        return;
    }
  }

  Future<_JwtRefresh?> _refreshJwtIfNeeded(
    EngineContext ctx,
    JwtPayload payload,
    AuthUser user,
  ) async {
    final updateAge = options.sessionUpdateAge;
    if (updateAge == null) {
      return null;
    }
    final issuedAtValue = payload.claims['iat'];
    final issuedAt = jwtIssuedAtUtc(issuedAtValue);
    if (issuedAt == null) {
      return null;
    }
    if (!shouldRefreshJwtByIssuedAt(issuedAtValue, updateAge)) {
      return null;
    }
    final issuer = _jwtIssuer();
    final claims = await _applyJwtCallback(
      AuthJwtCallbackContext<EngineContext>(
        context: ctx,
        token: Map<String, dynamic>.from(payload.claims),
        user: user,
        strategy: AuthSessionStrategy.jwt,
      ),
    );
    final token = issuer.issue(claims);
    ctx.response.cookies.add(
      buildJwtTokenCookie(
        options.jwtOptions.cookieName,
        token,
        expires: issuer.expiry,
      ),
    );
    return _JwtRefresh(token: token, expiresAt: issuer.expiry);
  }

  DateTime? _sessionExpiry(EngineContext ctx) {
    return resolveAuthSessionExpiry(
      sessionMaxAge: options.sessionMaxAge,
      sessionOptionsMaxAgeSeconds: ctx.session.options.maxAge,
    );
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
}

class _JwtRefresh {
  const _JwtRefresh({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}
