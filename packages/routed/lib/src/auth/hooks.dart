import 'dart:async';

import 'dart:async';

import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/events/event.dart';

/// Callback invoked before completing a sign-in flow.
typedef AuthSignInCallback =
    FutureOr<AuthSignInResult> Function(AuthSignInCallbackContext context);

/// Callback invoked to resolve redirect targets.
typedef AuthRedirectCallback =
    FutureOr<String?> Function(AuthRedirectCallbackContext context);

/// Callback invoked to customize JWT claims.
typedef AuthJwtCallback =
    FutureOr<Map<String, dynamic>?> Function(AuthJwtCallbackContext context);

/// Callback invoked to customize session payloads.
typedef AuthSessionCallback =
    FutureOr<Map<String, dynamic>?> Function(
      AuthSessionCallbackContext context,
    );

/// Container for auth callbacks.
class AuthCallbacks {
  const AuthCallbacks({this.signIn, this.redirect, this.jwt, this.session});

  final AuthSignInCallback? signIn;
  final AuthRedirectCallback? redirect;
  final AuthJwtCallback? jwt;
  final AuthSessionCallback? session;

  bool get isEmpty =>
      signIn == null && redirect == null && jwt == null && session == null;
}

/// Result of a sign-in callback decision.
class AuthSignInResult {
  const AuthSignInResult._(this.allowed, this.redirectUrl);

  const AuthSignInResult.allow({this.redirectUrl}) : allowed = true;

  const AuthSignInResult.deny() : allowed = false, redirectUrl = null;

  final bool allowed;
  final String? redirectUrl;
}

/// Context passed to sign-in callbacks.
class AuthSignInCallbackContext {
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

  final EngineContext context;
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
class AuthRedirectCallbackContext {
  AuthRedirectCallbackContext({
    required this.context,
    required this.url,
    required this.baseUrl,
    this.provider,
  });

  final EngineContext context;
  final String url;
  final String baseUrl;
  final AuthProvider? provider;
}

/// Context passed to JWT callbacks.
class AuthJwtCallbackContext {
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

  final EngineContext context;
  final Map<String, dynamic> token;
  final AuthUser user;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
  final AuthAccount? account;
  final Map<String, dynamic>? profile;
  final bool isNewUser;
}

/// Context passed to session callbacks.
class AuthSessionCallbackContext {
  AuthSessionCallbackContext({
    required this.context,
    required this.session,
    required this.payload,
    required this.user,
    required this.strategy,
    this.provider,
  });

  final EngineContext context;
  final AuthSession session;
  final Map<String, dynamic> payload;
  final AuthUser user;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
}

/// Event emitted after a successful sign-in.
final class AuthSignInEvent extends Event {
  AuthSignInEvent({
    required this.context,
    required this.user,
    required this.session,
    required this.strategy,
    this.provider,
    this.account,
    this.profile,
    this.credentials,
    this.redirectUrl,
    this.isNewUser = false,
  }) : super();

  final EngineContext context;
  final AuthUser user;
  final AuthSession session;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
  final AuthAccount? account;
  final Map<String, dynamic>? profile;
  final AuthCredentials? credentials;
  final String? redirectUrl;
  final bool isNewUser;
}

/// Event emitted after a sign-out flow completes.
final class AuthSignOutEvent extends Event {
  AuthSignOutEvent({
    required this.context,
    required this.strategy,
    this.session,
    this.user,
  }) : super();

  final EngineContext context;
  final AuthSessionStrategy strategy;
  final AuthSession? session;
  final AuthUser? user;
}

/// Event emitted when a new user is created.
final class AuthCreateUserEvent extends Event {
  AuthCreateUserEvent({
    required this.context,
    required this.user,
    this.provider,
    this.profile,
  }) : super();

  final EngineContext context;
  final AuthUser user;
  final AuthProvider? provider;
  final Map<String, dynamic>? profile;
}

/// Event emitted when a user is updated.
final class AuthUpdateUserEvent extends Event {
  AuthUpdateUserEvent({
    required this.context,
    required this.user,
    this.provider,
  }) : super();

  final EngineContext context;
  final AuthUser user;
  final AuthProvider? provider;
}

/// Event emitted when a provider account is linked.
final class AuthLinkAccountEvent extends Event {
  AuthLinkAccountEvent({
    required this.context,
    required this.account,
    this.user,
    this.profile,
  }) : super();

  final EngineContext context;
  final AuthAccount account;
  final AuthUser? user;
  final Map<String, dynamic>? profile;
}

/// Event emitted when a session payload is produced.
final class AuthSessionEvent extends Event {
  AuthSessionEvent({
    required this.context,
    required this.session,
    required this.payload,
    required this.strategy,
    this.provider,
  }) : super();

  final EngineContext context;
  final AuthSession session;
  final Map<String, dynamic> payload;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
}
