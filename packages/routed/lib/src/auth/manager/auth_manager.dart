import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show
        AuthAccount,
        AuthAdapter,
        AuthCallbacks,
        AuthCredentials,
        authorizeCredentialsRegistration,
        authorizeCredentialsSignIn,
        resolveAuthJwtClaimsWithCallbacks,
        resolveAuthRedirectWithCallbacks,
        resolveAuthSessionPayloadWithCallbacks,
        resolveAuthSignInRedirectWithCallbacks,
        issueAuthJwtSessionWithCallbacks,
        AuthPrincipal,
        AuthProvider,
        authProviderSummaries,
        baseUrlFromUri,
        resolveOAuthAuthorizationStart,
        resolveOAuthCallbackSignInForProvider,
        resolveAuthProviderById,
        AuthResult,
        AuthSession,
        AuthSessionStrategy,
        AuthFlowException,
        AuthUser,
        AuthVerificationTokenStore,
        InMemoryAuthVerificationTokenStore,
        resolveAuthEmailVerificationSignIn,
        startAuthEmailSignIn,
        resolveBearerOrCookieToken,
        resolveCsrfToken,
        validateCsrfToken,
        CallbackProvider,
        CredentialsProvider,
        EmailProvider,
        refreshAuthJwtTokenIfNeeded,
        verifyAuthJwtSessionToken,
        JwtPayload,
        OAuthProvider,
        authSessionIssuedAtKey,
        AuthOptions,
        resolveAuthSessionMaxAgeSeconds,
        resolveAuthSessionExpiry,
        serializeAuthSessionIssuedAt,
        syncAuthSessionRefresh,
        secureRandomToken;
import 'package:routed/src/auth/hooks.dart';
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/events/event.dart';
import 'package:routed/src/events/event_manager.dart';

/// High-level auth coordinator for routed.
class AuthManager {
  AuthManager(this.options, {SessionAuthService? sessionAuth})
    : _tokenStore = options.tokenStore ?? InMemoryAuthVerificationTokenStore(),
      _sessionAuth = sessionAuth,
      _httpClient = options.httpClient;

  final AuthOptions<EngineContext> options;
  final AuthVerificationTokenStore _tokenStore;
  final SessionAuthService? _sessionAuth;
  http.Client? _httpClient;

  AuthAdapter get adapter => options.adapter;

  SessionAuthService get sessionAuth => _sessionAuth ?? SessionAuth.instance;

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
    final payload = await startAuthEmailSignIn<EngineContext>(
      adapter: adapter,
      tokenStore: _tokenStore,
      provider: provider,
      context: ctx,
      email: email,
      callbackUrl: callbackUrl,
      sessionStrategy: options.sessionStrategy,
      generateToken: secureRandomToken,
      writeSession: ctx.setSession,
      callbackKey: options.callbackKey,
    );
    return payload.pendingResult;
  }

  Future<AuthResult> verifyEmail(
    EngineContext ctx,
    EmailProvider provider,
    String email,
    String token,
  ) async {
    final resolved = await resolveAuthEmailVerificationSignIn(
      adapter: adapter,
      tokenStore: _tokenStore,
      email: email,
      token: token,
      callbackKey: options.callbackKey,
      readSession: (key) => ctx.getSession<String>(key),
    );
    if (resolved == null) {
      throw AuthFlowException('invalid_token');
    }

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
    final resolved =
        await resolveOAuthAuthorizationStart<EngineContext, TProfile>(
          context: ctx,
          provider: provider,
          stateKey: options.stateKey,
          pkceKey: options.pkceKey,
          callbackKey: options.callbackKey,
          callbackUrl: callbackUrl,
          writeSession: ctx.setSession,
        );
    return resolved.authorizationUri;
  }

  Future<AuthResult> finishOAuth<TProfile extends Object>(
    EngineContext ctx,
    OAuthProvider<TProfile> provider,
    String code,
    String? state,
  ) async {
    final resolved =
        await resolveOAuthCallbackSignInForProvider<EngineContext, TProfile>(
          adapter: adapter,
          context: ctx,
          provider: provider,
          code: code,
          receivedState: state,
          stateKey: options.stateKey,
          pkceKey: options.pkceKey,
          callbackKey: options.callbackKey,
          readSession: (key) => ctx.getSession<String>(key),
          httpClient: httpClient,
          fallbackAccountId: secureRandomToken,
        );
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
        final issued = await issueAuthJwtSessionWithCallbacks<EngineContext>(
          callbacks: callbacks,
          context: ctx,
          options: options.jwtOptions,
          user: user,
          strategy: AuthSessionStrategy.jwt,
        );
        ctx.response.cookies.add(issued.issued.cookie);
        return issued.session;
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
        final verified = await verifyAuthJwtSessionToken(
          token: token,
          options: options.jwtOptions,
          httpClient: httpClient,
        );
        if (verified == null) {
          return null;
        }
        final user = verified.user;
        var resolvedToken = verified.token;
        var resolvedExpiry = verified.expiresAt;
        final refreshed = await _refreshJwtIfNeeded(
          ctx,
          verified.payload,
          user,
        );
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
    final resolvedDecisionRedirect =
        await resolveAuthSignInRedirectWithCallbacks<EngineContext>(
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
        );

    final resolvedRedirect = await resolveRedirect(
      ctx,
      resolvedDecisionRedirect ?? redirectUrl,
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
        final issued = await issueAuthJwtSessionWithCallbacks<EngineContext>(
          callbacks: callbacks,
          context: ctx,
          options: options.jwtOptions,
          user: user,
          strategy: AuthSessionStrategy.jwt,
          provider: provider,
          account: account,
          profile: profile,
          isNewUser: isNewUser,
        );
        ctx.response.cookies.add(issued.issued.cookie);
        final session = issued.session;
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

  void _refreshSessionIfNeeded(EngineContext ctx) {
    syncAuthSessionRefresh(
      issuedAtValue: ctx.getSession<String>(authSessionIssuedAtKey),
      updateAge: options.sessionUpdateAge,
      writeIssuedAt: (issuedAtUtc) => _setSessionIssuedAt(ctx, issuedAtUtc),
      touchSession: ctx.session.touch,
    );
  }

  Future<_JwtRefresh?> _refreshJwtIfNeeded(
    EngineContext ctx,
    JwtPayload payload,
    AuthUser user,
  ) async {
    final refreshed = await refreshAuthJwtTokenIfNeeded(
      options: options.jwtOptions,
      claims: payload.claims,
      updateAge: options.sessionUpdateAge,
      resolveClaims: (claims) =>
          resolveAuthJwtClaimsWithCallbacks<EngineContext>(
            callbacks: callbacks,
            context: ctx,
            user: user,
            strategy: AuthSessionStrategy.jwt,
            token: claims,
          ),
    );
    if (refreshed == null) {
      return null;
    }
    ctx.response.cookies.add(refreshed.cookie);
    return _JwtRefresh(token: refreshed.token, expiresAt: refreshed.expiresAt);
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
