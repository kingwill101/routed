import 'dart:async';

import 'exceptions.dart';
import 'jwt.dart';
import 'models.dart';
import 'providers.dart';
import 'users.dart';

/// Callback invoked before completing a sign-in flow.
typedef AuthSignInCallback<TContext> =
    FutureOr<AuthSignInResult> Function(
      AuthSignInCallbackContext<TContext> context,
    );

/// Callback invoked to resolve redirect targets.
typedef AuthRedirectCallback<TContext> =
    FutureOr<String?> Function(AuthRedirectCallbackContext<TContext> context);

/// Callback invoked to customize JWT claims.
typedef AuthJwtCallback<TContext> =
    FutureOr<Map<String, dynamic>?> Function(
      AuthJwtCallbackContext<TContext> context,
    );

/// Callback invoked to customize session payloads.
typedef AuthSessionCallback<TContext> =
    FutureOr<Map<String, dynamic>?> Function(
      AuthSessionCallbackContext<TContext> context,
    );

/// Container for auth callbacks.
class AuthCallbacks<TContext> {
  const AuthCallbacks({this.signIn, this.redirect, this.jwt, this.session});

  final AuthSignInCallback<TContext>? signIn;
  final AuthRedirectCallback<TContext>? redirect;
  final AuthJwtCallback<TContext>? jwt;
  final AuthSessionCallback<TContext>? session;

  bool get isEmpty =>
      signIn == null && redirect == null && jwt == null && session == null;
}

/// Evaluates sign-in callback behavior with built-in allow-by-default logic.
Future<AuthSignInResult> resolveAuthSignInDecision<TContext>({
  required AuthSignInCallback<TContext>? callback,
  required AuthSignInCallbackContext<TContext> context,
}) async {
  if (callback == null) {
    return const AuthSignInResult.allow();
  }
  return await Future<AuthSignInResult>.value(callback(context));
}

/// Resolves sign-in decision and returns redirect when allowed.
///
/// Throws [AuthFlowException] when the decision denies sign-in.
Future<String?> resolveAuthSignInRedirectOrThrow<TContext>({
  required AuthSignInCallback<TContext>? callback,
  required AuthSignInCallbackContext<TContext> context,
  String blockedCode = 'sign_in_blocked',
}) async {
  final decision = await resolveAuthSignInDecision<TContext>(
    callback: callback,
    context: context,
  );
  if (!decision.allowed) {
    throw AuthFlowException(blockedCode);
  }
  return decision.redirectUrl;
}

/// Resolves sign-in callback using [callbacks.signIn], returning redirect when
/// allowed and throwing [AuthFlowException] when denied.
Future<String?> resolveAuthSignInRedirectWithCallbacks<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required AuthUser user,
  required AuthSessionStrategy strategy,
  AuthProvider? provider,
  AuthAccount? account,
  Map<String, dynamic>? profile,
  AuthCredentials? credentials,
  bool isNewUser = false,
  String? callbackUrl,
  String blockedCode = 'sign_in_blocked',
}) {
  return resolveAuthSignInRedirectOrThrow<TContext>(
    callback: callbacks.signIn,
    context: AuthSignInCallbackContext<TContext>(
      context: context,
      user: user,
      strategy: strategy,
      provider: provider,
      account: account,
      profile: profile,
      credentials: credentials,
      isNewUser: isNewUser,
      callbackUrl: callbackUrl,
    ),
    blockedCode: blockedCode,
  );
}

/// Resolves the final sign-in redirect by combining sign-in callback decision
/// and adapter-specific redirect resolution.
Future<String?> resolveAuthSignInRedirectTarget<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required AuthUser user,
  required AuthSessionStrategy strategy,
  required FutureOr<String?> Function(String? candidate) resolveRedirect,
  AuthProvider? provider,
  AuthAccount? account,
  Map<String, dynamic>? profile,
  AuthCredentials? credentials,
  bool isNewUser = false,
  String? callbackUrl,
  String blockedCode = 'sign_in_blocked',
}) async {
  final decidedRedirect =
      await resolveAuthSignInRedirectWithCallbacks<TContext>(
        callbacks: callbacks,
        context: context,
        user: user,
        strategy: strategy,
        provider: provider,
        account: account,
        profile: profile,
        credentials: credentials,
        isNewUser: isNewUser,
        callbackUrl: callbackUrl,
        blockedCode: blockedCode,
      );

  final target = decidedRedirect ?? callbackUrl;
  return await Future<String?>.value(resolveRedirect(target));
}

/// Evaluates JWT callback behavior with pass-through defaults.
Future<Map<String, dynamic>> resolveAuthJwtClaims<TContext>({
  required AuthJwtCallback<TContext>? callback,
  required AuthJwtCallbackContext<TContext> context,
}) async {
  if (callback == null) {
    return context.token;
  }
  final updated = await Future<Map<String, dynamic>?>.value(callback(context));
  return updated ?? context.token;
}

/// Evaluates session callback behavior with pass-through defaults.
Future<Map<String, dynamic>> resolveAuthSessionPayload<TContext>({
  required AuthSessionCallback<TContext>? callback,
  required AuthSessionCallbackContext<TContext> context,
}) async {
  if (callback == null) {
    return context.payload;
  }
  final updated = await Future<Map<String, dynamic>?>.value(callback(context));
  return updated ?? context.payload;
}

/// Evaluates redirect callback behavior.
Future<String?> resolveAuthRedirectTarget<TContext>({
  required AuthRedirectCallback<TContext>? callback,
  required AuthRedirectCallbackContext<TContext> context,
}) async {
  if (callback == null) {
    return null;
  }
  return await Future<String?>.value(callback(context));
}

/// Evaluates redirect callback behavior with fallback pass-through semantics.
Future<String?> resolveAuthRedirectTargetWithFallback<TContext>({
  required AuthRedirectCallback<TContext>? callback,
  required AuthRedirectCallbackContext<TContext> context,
  String? fallbackUrl,
}) async {
  final resolved = await resolveAuthRedirectTarget<TContext>(
    callback: callback,
    context: context,
  );
  return resolved ?? fallbackUrl;
}

/// Resolves redirect URL through [callbacks.redirect] with pass-through
/// fallback behavior.
Future<String?> resolveAuthRedirectWithCallbacks<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required String? url,
  required String baseUrl,
  AuthProvider? provider,
}) async {
  if (url == null || url.trim().isEmpty) {
    return null;
  }
  return resolveAuthRedirectTargetWithFallback<TContext>(
    callback: callbacks.redirect,
    context: AuthRedirectCallbackContext<TContext>(
      context: context,
      url: url,
      baseUrl: baseUrl,
      provider: provider,
    ),
    fallbackUrl: url,
  );
}

/// Resolves JWT claims through [callbacks.jwt] using standard auth context.
Future<Map<String, dynamic>> resolveAuthJwtClaimsWithCallbacks<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required AuthUser user,
  required AuthSessionStrategy strategy,
  AuthProvider? provider,
  AuthAccount? account,
  Map<String, dynamic>? profile,
  bool isNewUser = false,
  Map<String, dynamic>? token,
}) async {
  final baseToken = Map<String, dynamic>.from(
    token ?? authJwtClaimsForUser(user),
  );
  return resolveAuthJwtClaims<TContext>(
    callback: callbacks.jwt,
    context: AuthJwtCallbackContext<TContext>(
      context: context,
      token: baseToken,
      user: user,
      strategy: strategy,
      provider: provider,
      account: account,
      profile: profile,
      isNewUser: isNewUser,
    ),
  );
}

/// Resolves session payload through [callbacks.session] using standard auth
/// session callback context.
Future<Map<String, dynamic>> resolveAuthSessionPayloadWithCallbacks<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required AuthSession session,
  required AuthSessionStrategy strategy,
  AuthProvider? provider,
  Map<String, dynamic>? payload,
}) async {
  final basePayload = Map<String, dynamic>.from(payload ?? session.toJson());
  return resolveAuthSessionPayload<TContext>(
    callback: callbacks.session,
    context: AuthSessionCallbackContext<TContext>(
      context: context,
      session: session,
      payload: basePayload,
      user: session.user,
      strategy: strategy,
      provider: provider,
    ),
  );
}

/// Result of issuing a JWT session with callbacks.
class AuthJwtSessionIssue {
  const AuthJwtSessionIssue({
    required this.claims,
    required this.issued,
    required this.session,
  });

  final Map<String, dynamic> claims;
  final AuthIssuedJwtToken issued;
  final AuthSession session;
}

/// Result of resolving a sign-in response for a session strategy.
class AuthResolvedSignInResult {
  const AuthResolvedSignInResult({required this.result, this.issuedJwt});

  final AuthResult result;
  final AuthIssuedJwtToken? issuedJwt;
}

/// Issues a JWT-backed auth session using callback-driven claims resolution.
Future<AuthJwtSessionIssue> issueAuthJwtSessionWithCallbacks<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required JwtSessionOptions options,
  required AuthUser user,
  AuthSessionStrategy strategy = AuthSessionStrategy.jwt,
  AuthProvider? provider,
  AuthAccount? account,
  Map<String, dynamic>? profile,
  bool isNewUser = false,
  Map<String, dynamic>? token,
}) async {
  if (options.secret.isEmpty) {
    throw AuthFlowException('missing_jwt_secret');
  }

  final claims = await resolveAuthJwtClaimsWithCallbacks<TContext>(
    callbacks: callbacks,
    context: context,
    user: user,
    strategy: strategy,
    provider: provider,
    account: account,
    profile: profile,
    isNewUser: isNewUser,
    token: token,
  );

  final issued = issueAuthJwtToken(options: options, claims: claims);
  return AuthJwtSessionIssue(
    claims: claims,
    issued: issued,
    session: AuthSession(
      user: user,
      expiresAt: issued.expiresAt,
      strategy: strategy,
      token: issued.token,
    ),
  );
}

/// Resolves a sign-in [AuthResult] for the selected strategy.
///
/// For [AuthSessionStrategy.session], returns a session-backed result using
/// [sessionExpiresAt].
///
/// For [AuthSessionStrategy.jwt], issues a JWT via
/// [issueAuthJwtSessionWithCallbacks] and returns the resulting cookie/token in
/// [AuthResolvedSignInResult.issuedJwt].
Future<AuthResolvedSignInResult>
resolveAuthSignInResultForStrategyWithCallbacks<TContext>({
  required AuthCallbacks<TContext> callbacks,
  required TContext context,
  required AuthSessionStrategy strategy,
  required AuthUser user,
  required String? redirectUrl,
  required JwtSessionOptions jwtOptions,
  DateTime? sessionExpiresAt,
  AuthProvider? provider,
  AuthAccount? account,
  Map<String, dynamic>? profile,
  bool isNewUser = false,
  Map<String, dynamic>? token,
}) async {
  switch (strategy) {
    case AuthSessionStrategy.session:
      final session = AuthSession(
        user: user,
        expiresAt: sessionExpiresAt,
        strategy: AuthSessionStrategy.session,
      );
      return AuthResolvedSignInResult(
        result: AuthResult(
          user: user,
          session: session,
          redirectUrl: redirectUrl,
        ),
      );
    case AuthSessionStrategy.jwt:
      final issued = await issueAuthJwtSessionWithCallbacks<TContext>(
        callbacks: callbacks,
        context: context,
        options: jwtOptions,
        user: user,
        strategy: AuthSessionStrategy.jwt,
        provider: provider,
        account: account,
        profile: profile,
        isNewUser: isNewUser,
        token: token,
      );
      return AuthResolvedSignInResult(
        result: AuthResult(
          user: user,
          session: issued.session,
          redirectUrl: redirectUrl,
        ),
        issuedJwt: issued.issued,
      );
  }
}

/// Result of a sign-in callback decision.
class AuthSignInResult {
  const AuthSignInResult.allow({this.redirectUrl}) : allowed = true;

  const AuthSignInResult.deny() : allowed = false, redirectUrl = null;

  final bool allowed;
  final String? redirectUrl;
}

/// Context passed to sign-in callbacks.
class AuthSignInCallbackContext<TContext> {
  AuthSignInCallbackContext({
    required this.context,
    required this.user,
    required this.strategy,
    this.provider,
    this.account,
    this.profile,
    this.credentials,
    this.isNewUser = false,
    this.callbackUrl,
  });

  final TContext context;
  final AuthUser user;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
  final AuthAccount? account;
  final Map<String, dynamic>? profile;
  final AuthCredentials? credentials;
  final bool isNewUser;
  final String? callbackUrl;
}

/// Context passed to redirect callbacks.
class AuthRedirectCallbackContext<TContext> {
  AuthRedirectCallbackContext({
    required this.context,
    required this.url,
    required this.baseUrl,
    this.provider,
  });

  final TContext context;
  final String url;
  final String baseUrl;
  final AuthProvider? provider;
}

/// Context passed to JWT callbacks.
class AuthJwtCallbackContext<TContext> {
  AuthJwtCallbackContext({
    required this.context,
    required this.token,
    required this.user,
    required this.strategy,
    this.provider,
    this.account,
    this.profile,
    this.isNewUser = false,
  });

  final TContext context;
  final Map<String, dynamic> token;
  final AuthUser user;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
  final AuthAccount? account;
  final Map<String, dynamic>? profile;
  final bool isNewUser;
}

/// Context passed to session callbacks.
class AuthSessionCallbackContext<TContext> {
  AuthSessionCallbackContext({
    required this.context,
    required this.session,
    required this.payload,
    required this.user,
    required this.strategy,
    this.provider,
  });

  final TContext context;
  final AuthSession session;
  final Map<String, dynamic> payload;
  final AuthUser user;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
}
