import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:routed/src/auth/adapter.dart';
import 'package:routed/src/auth/hooks.dart';
import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/auth/jwt.dart';
import 'package:routed/src/auth/oauth.dart';
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/events/event.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/crypto/crypto.dart';

import 'auth_options.dart';
import 'verification_token_store.dart';

/// {@macro routed_auth_manager}
class AuthManager {
  static const String _sessionIssuedAtKey = '_auth.session.issued_at';

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

  AuthCallbacks get callbacks => options.callbacks;

  AuthProvider? resolveProvider(String id) {
    for (final provider in options.providers) {
      if (provider.id == id) {
        return provider;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> providerSummaries() {
    return options.providers
        .map((provider) => provider.toJson())
        .toList(growable: false);
  }

  String csrfToken(EngineContext ctx) {
    final existing = ctx.getSession<String>(options.csrfKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final token = _randomToken();
    ctx.setSession(options.csrfKey, token);
    return token;
  }

  bool validateCsrf(EngineContext ctx, Map<String, dynamic> payload) {
    if (!options.enforceCsrf) {
      return true;
    }
    final expected = ctx.getSession<String>(options.csrfKey);
    if (expected == null || expected.isEmpty) {
      return false;
    }
    final header =
        ctx.request.headers.value('x-csrf-token') ??
        ctx.request.headers.value('X-CSRF-Token');
    final formToken = payload['_csrf']?.toString();
    final token = header ?? formToken;
    return token != null && token == expected;
  }

  Future<AuthResult> signInWithCredentials(
    EngineContext ctx,
    CredentialsProvider provider,
    AuthCredentials credentials,
  ) async {
    final user = provider.authorize != null
        ? await Future.sync(
            () => provider.authorize!(ctx, provider, credentials),
          )
        : await Future.sync(() => adapter.verifyCredentials(credentials));

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
    final user = provider.register != null
        ? await Future.sync(
            () => provider.register!(ctx, provider, credentials),
          )
        : await Future.sync(() => adapter.registerCredentials(credentials));

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
    await Future.sync(() => adapter.deleteVerificationTokens(email));
    await _tokenStore.delete(email);
    final token = provider.tokenGenerator?.call() ?? _randomToken();
    final expiresAt = DateTime.now().add(provider.tokenExpiry);
    if (callbackUrl.isNotEmpty) {
      ctx.setSession('${options.callbackKey}.email', callbackUrl);
    }
    final verification = AuthVerificationToken(
      identifier: email,
      token: token,
      expiresAt: expiresAt,
    );
    await Future.sync(() => adapter.saveVerificationToken(verification));
    await _tokenStore.save(verification);

    final request = AuthEmailRequest(
      email: email,
      token: token,
      callbackUrl: callbackUrl,
      expiresAt: expiresAt,
    );
    await Future.sync(
      () => provider.sendVerificationRequest(ctx, provider, request),
    );

    final session = AuthSession(
      user: AuthUser(id: '', email: email),
      expiresAt: expiresAt,
      strategy: options.sessionStrategy,
    );
    return AuthResult(user: session.user, session: session);
  }

  Future<AuthResult> verifyEmail(
    EngineContext ctx,
    EmailProvider provider,
    String email,
    String token,
  ) async {
    final verification = await Future.sync(
      () => adapter.useVerificationToken(email, token),
    );
    final fallback = await _tokenStore.use(email, token);
    final resolved = verification ?? fallback;
    if (resolved == null) {
      throw AuthFlowException('invalid_token');
    }

    final existing = await Future.sync(() => adapter.getUserByEmail(email));
    var isNewUser = false;
    late final AuthUser user;
    if (existing != null) {
      user = existing;
    } else {
      user = await Future.sync(
        () => adapter.createUser(AuthUser(id: email, email: email)),
      );
      isNewUser = true;
    }
    final redirectUrl = ctx.getSession<String>('${options.callbackKey}.email');

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
    final state = _randomToken();
    ctx.setSession('${options.stateKey}.${provider.id}', state);

    if (provider.onStateGenerated != null) {
      await Future.sync(() => provider.onStateGenerated!(ctx, provider, state));
    }

    String? verifier;
    String? challenge;
    if (provider.usePkce) {
      verifier = _randomToken(length: 48);
      challenge = _base64Url(sha256Bytes(verifier));
      ctx.setSession('${options.pkceKey}.${provider.id}', verifier);
    }

    final params = <String, String>{
      'response_type': 'code',
      'client_id': provider.clientId,
      'redirect_uri': provider.redirectUri,
      'state': state,
      if (provider.scopes.isNotEmpty) 'scope': provider.scopes.join(' '),
      if (challenge != null) 'code_challenge': challenge,
      if (challenge != null) 'code_challenge_method': 'S256',
      ...provider.authorizationParams,
    };

    if (callbackUrl != null && callbackUrl.isNotEmpty) {
      ctx.setSession('${options.callbackKey}.${provider.id}', callbackUrl);
      params['callbackUrl'] = callbackUrl;
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
      '${options.stateKey}.${provider.id}',
    );
    if (expectedState == null || expectedState != state) {
      throw AuthFlowException('invalid_state');
    }

    final verifier = ctx.getSession<String>(
      '${options.pkceKey}.${provider.id}',
    );
    final tokenResponse = await _exchangeOAuthCode(provider, code, verifier);

    final rawProfile = await _loadOAuthProfile(ctx, provider, tokenResponse);
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
    final accountId = _resolveAccountId(profileMap, user);
    final accountExpiresAt = tokenResponse.expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: tokenResponse.expiresIn!));

    final existingAccount = await Future.sync(
      () => adapter.getAccount(provider.id, accountId),
    );

    var isNewUser = false;
    AuthUser resolvedUser = user;
    if (existingAccount != null && existingAccount.userId != null) {
      final byId = await Future.sync(
        () => adapter.getUserById(existingAccount.userId!),
      );
      if (byId != null) {
        resolvedUser = byId;
      }
    }

    if (resolvedUser.email != null) {
      final byEmail = await Future.sync(
        () => adapter.getUserByEmail(resolvedUser.email!),
      );
      if (byEmail != null) {
        resolvedUser = byEmail;
      }
    }

    if (resolvedUser.id.isEmpty) {
      resolvedUser = await Future.sync(() => adapter.createUser(resolvedUser));
      isNewUser = true;
    } else {
      final updatedUser = _mergeUser(resolvedUser, user);
      if (_hasUserChanges(resolvedUser, updatedUser)) {
        final stored = await Future.sync(() => adapter.updateUser(updatedUser));
        resolvedUser = stored ?? updatedUser;
        await _emitAuthEvent(
          ctx,
          AuthUpdateUserEvent(
            context: ctx,
            user: resolvedUser,
            provider: provider,
          ),
        );
      }
    }

    final account = AuthAccount(
      providerId: provider.id,
      providerAccountId: accountId,
      userId: resolvedUser.id,
      accessToken: tokenResponse.accessToken,
      refreshToken: tokenResponse.refreshToken,
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
      '${options.callbackKey}.${provider.id}',
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
          AuthJwtCallbackContext(
            context: ctx,
            token: _jwtClaimsForUser(user),
            user: user,
            strategy: AuthSessionStrategy.jwt,
          ),
        );
        final token = issuer.issue(claims);
        _attachJwtCookie(ctx, token, issuer.expiry);
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
        final user = _userFromJwtClaims(payload.claims);
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

  Future<AuthSignInResult> _applySignInCallback(
    AuthSignInCallbackContext context,
  ) async {
    final callback = callbacks.signIn;
    if (callback == null) {
      return const AuthSignInResult.allow();
    }
    return await Future.sync(() => callback(context));
  }

  Future<Map<String, dynamic>> _applyJwtCallback(
    AuthJwtCallbackContext context,
  ) async {
    final callback = callbacks.jwt;
    if (callback == null) {
      return context.token;
    }
    final updated = await Future.sync(() => callback(context));
    return updated ?? context.token;
  }

  Future<String?> resolveRedirect(
    EngineContext ctx,
    String? url, {
    AuthProvider? provider,
  }) async {
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    final callback = callbacks.redirect;
    if (callback == null) {
      return url;
    }
    final resolved = await Future.sync(
      () => callback(
        AuthRedirectCallbackContext(
          context: ctx,
          url: url,
          baseUrl: _baseUrl(ctx.request.uri),
          provider: provider,
        ),
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
    final callback = callbacks.session;
    final resolved = callback == null
        ? null
        : await Future.sync(
            () => callback(
              AuthSessionCallbackContext(
                context: ctx,
                session: session,
                payload: payload,
                user: session.user,
                strategy: session.strategy ?? options.sessionStrategy,
                provider: provider,
              ),
            ),
          );
    final finalPayload = resolved ?? payload;
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

  String _baseUrl(Uri uri) {
    final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://$host$port';
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
    final decision = await _applySignInCallback(
      AuthSignInCallbackContext(
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
          AuthJwtCallbackContext(
            context: ctx,
            token: _jwtClaimsForUser(user),
            user: user,
            strategy: AuthSessionStrategy.jwt,
            provider: provider,
            account: account,
            profile: profile,
            isNewUser: isNewUser,
          ),
        );
        final token = issuer.issue(claims);
        _attachJwtCookie(ctx, token, issuer.expiry);
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

  Map<String, dynamic> _jwtClaimsForUser(AuthUser user) {
    return {
      'sub': user.id,
      'email': user.email,
      'name': user.name,
      'image': user.image,
      'roles': user.roles,
      'attributes': user.attributes,
    };
  }

  AuthUser _userFromJwtClaims(Map<String, dynamic> claims) {
    return AuthUser(
      id: claims['sub']?.toString() ?? '',
      email: claims['email']?.toString(),
      name: claims['name']?.toString(),
      image: claims['image']?.toString(),
      roles: (claims['roles'] as List?)?.cast<String>() ?? const <String>[],
      attributes: (claims['attributes'] as Map?)?.cast<String, dynamic>(),
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
    ctx.setSession(_sessionIssuedAtKey, issuedAt.toIso8601String());
  }

  DateTime? _sessionIssuedAt(EngineContext ctx) {
    final stored = ctx.getSession<String>(_sessionIssuedAtKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    return DateTime.tryParse(stored)?.toUtc();
  }

  void _refreshSessionIfNeeded(EngineContext ctx) {
    final updateAge = options.sessionUpdateAge;
    if (updateAge == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final issuedAt = _sessionIssuedAt(ctx);
    if (issuedAt == null) {
      _setSessionIssuedAt(ctx, now);
      return;
    }
    if (now.difference(issuedAt) >= updateAge) {
      _setSessionIssuedAt(ctx, now);
      ctx.session.touch();
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
    if (issuedAtValue is! num) {
      return null;
    }
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(
      issuedAtValue.toInt() * 1000,
      isUtc: true,
    ).toUtc();
    if (DateTime.now().toUtc().difference(issuedAt) < updateAge) {
      return null;
    }
    final issuer = _jwtIssuer();
    final claims = await _applyJwtCallback(
      AuthJwtCallbackContext(
        context: ctx,
        token: Map<String, dynamic>.from(payload.claims),
        user: user,
        strategy: AuthSessionStrategy.jwt,
      ),
    );
    final token = issuer.issue(claims);
    _attachJwtCookie(ctx, token, issuer.expiry);
    return _JwtRefresh(token: token, expiresAt: issuer.expiry);
  }

  DateTime? _sessionExpiry(EngineContext ctx) {
    final override = options.sessionMaxAge;
    if (override != null) {
      return DateTime.now().add(override);
    }
    final maxAge = ctx.session.options.maxAge;
    if (maxAge == null || maxAge <= 0) {
      return null;
    }
    return DateTime.now().add(Duration(seconds: maxAge));
  }

  String? _resolveJwtToken(EngineContext ctx) {
    final header = ctx.request.headers.value(options.jwtOptions.header);
    if (header != null && header.startsWith(options.jwtOptions.bearerPrefix)) {
      return header.substring(options.jwtOptions.bearerPrefix.length).trim();
    }
    for (final cookie in ctx.request.cookies) {
      if (cookie.name == options.jwtOptions.cookieName) {
        return cookie.value;
      }
    }
    return null;
  }

  void _attachJwtCookie(EngineContext ctx, String token, DateTime? expires) {
    final cookie = Cookie(options.jwtOptions.cookieName, token)
      ..httpOnly = true
      ..path = '/';
    if (expires != null) {
      cookie.expires = expires;
    }
    ctx.response.cookies.add(cookie);
  }

  OAuth2Client _oauthClient<TProfile extends Object>(
    OAuthProvider<TProfile> provider,
  ) {
    return OAuth2Client(
      tokenEndpoint: provider.tokenEndpoint,
      clientId: provider.clientId,
      clientSecret: provider.clientSecret,
      httpClient: httpClient,
      useBasicAuth: provider.useBasicAuth,
    );
  }

  Future<OAuthTokenResponse> _exchangeOAuthCode<TProfile extends Object>(
    OAuthProvider<TProfile> provider,
    String code,
    String? verifier,
  ) async {
    final scope = provider.scopes.isEmpty ? null : provider.scopes.join(' ');
    return _oauthClient(provider).exchangeAuthorizationCode(
      code: code,
      redirectUri: Uri.parse(provider.redirectUri),
      codeVerifier: verifier,
      scope: scope,
      additionalParameters: provider.tokenParams.isEmpty
          ? null
          : provider.tokenParams,
    );
  }

  Future<Map<String, dynamic>> _loadOAuthProfile<TProfile extends Object>(
    EngineContext ctx,
    OAuthProvider<TProfile> provider,
    OAuthTokenResponse token,
  ) async {
    Map<String, dynamic> profile;
    if (provider.userInfoEndpoint == null) {
      final idToken = token.raw['id_token']?.toString();
      if (idToken != null && idToken.isNotEmpty) {
        final jwt = JsonWebToken.unverified(idToken);
        profile = jwt.claims.toJson();
      } else {
        profile = <String, dynamic>{};
      }
    } else if (provider.userInfoRequest != null) {
      // Use custom userinfo request callback (e.g., for POST-based endpoints)
      try {
        profile = await Future.sync(
          () => provider.userInfoRequest!(
            token,
            httpClient,
            provider.userInfoEndpoint!,
          ),
        );
      } catch (e) {
        throw AuthFlowException('userinfo_failed');
      }
    } else {
      try {
        profile = await _oauthClient(
          provider,
        ).fetchUserInfo(provider.userInfoEndpoint!, token.accessToken);
      } on OAuth2Exception {
        throw AuthFlowException('userinfo_failed');
      }
    }

    return profile;
  }

  String _resolveAccountId(Map<String, dynamic> profile, AuthUser user) {
    final candidates = [
      profile['sub'],
      profile['id'],
      profile['user_id'],
      user.id,
      user.email,
    ];
    return candidates
        .firstWhere(
          (value) => value != null && value.toString().isNotEmpty,
          orElse: () => _randomToken(),
        )
        .toString();
  }

  AuthUser _mergeUser(AuthUser existing, AuthUser incoming) {
    final roles = incoming.roles.isNotEmpty ? incoming.roles : existing.roles;
    final attributes = <String, dynamic>{
      ...existing.attributes,
      ...incoming.attributes,
    };
    return AuthUser(
      id: existing.id,
      email: incoming.email ?? existing.email,
      name: incoming.name ?? existing.name,
      image: incoming.image ?? existing.image,
      roles: roles,
      attributes: attributes,
    );
  }

  bool _hasUserChanges(AuthUser existing, AuthUser updated) {
    if (existing.email != updated.email ||
        existing.name != updated.name ||
        existing.image != updated.image) {
      return true;
    }
    if (!_listEquals(existing.roles, updated.roles)) {
      return true;
    }
    return !_mapEquals(existing.attributes, updated.attributes);
  }

  bool _listEquals(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  bool _mapEquals(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) {
        return false;
      }
      final rightValue = right[entry.key];
      if (rightValue != entry.value) {
        return false;
      }
    }
    return true;
  }

  String _randomToken({int length = 32}) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  List<int> sha256Bytes(String value) {
    final data = utf8.encode(value);
    return sha256Digest(data);
  }

  String _base64Url(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _JwtRefresh {
  const _JwtRefresh({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

class AuthFlowException implements Exception {
  AuthFlowException(this.code);

  final String code;

  @override
  String toString() => 'AuthFlowException($code)';
}
