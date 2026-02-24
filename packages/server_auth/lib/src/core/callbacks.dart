import 'dart:async';

import 'models.dart';
import 'providers.dart';

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
