// ignore_for_file: implementation_imports
import 'package:server_auth/server_auth.dart'
    show
        AuthAccount,
        AuthSession,
        AuthSessionStrategy,
        AuthUser,
        AuthCredentials,
        AuthProvider,
        sanitizeAuthPublicAttributes;
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/events/event.dart';

/// Event emitted after a successful sign-in.
///
/// Authentication model fields are redacted before the event is published;
/// credentials, provider secrets, account tokens, JWTs, and nested
/// secret-like values must not escape into event listeners or audit pipelines.
final class AuthSignInEvent extends Event {
  AuthSignInEvent({
    required this.context,
    required AuthUser user,
    required this.strategy,
    required AuthSession session,
    AuthProvider? provider,
    AuthAccount? account,
    Map<String, dynamic>? profile,
    AuthCredentials? credentials,
    this.redirectUrl,
    this.isNewUser = false,
  }) : user = user.redacted(),
       session = session.redacted(),
       provider = provider?.redacted(),
       credentials = credentials?.redacted(),
       account = account?.redacted(),
       profile = profile == null ? null : sanitizeAuthPublicAttributes(profile),
       super();

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
    AuthSession? session,
    AuthUser? user,
  }) : session = session?.redacted(),
       user = user?.redacted(),
       super();

  final EngineContext context;
  final AuthSessionStrategy strategy;
  final AuthSession? session;
  final AuthUser? user;
}

/// Event emitted when a new user is created.
final class AuthCreateUserEvent extends Event {
  AuthCreateUserEvent({
    required this.context,
    required AuthUser user,
    AuthProvider? provider,
    Map<String, dynamic>? profile,
  }) : user = user.redacted(),
       provider = provider?.redacted(),
       profile = profile == null ? null : sanitizeAuthPublicAttributes(profile),
       super();

  final EngineContext context;
  final AuthUser user;
  final AuthProvider? provider;
  final Map<String, dynamic>? profile;
}

/// Event emitted when a user is updated.
final class AuthUpdateUserEvent extends Event {
  AuthUpdateUserEvent({
    required this.context,
    required AuthUser user,
    AuthProvider? provider,
  }) : user = user.redacted(),
       provider = provider?.redacted(),
       super();

  final EngineContext context;
  final AuthUser user;
  final AuthProvider? provider;
}

/// Event emitted when a provider account is linked.
final class AuthLinkAccountEvent extends Event {
  AuthLinkAccountEvent({
    required this.context,
    required AuthAccount account,
    AuthUser? user,
    AuthProvider? provider,
    Map<String, dynamic>? profile,
  }) : account = account.redacted(),
       user = user?.redacted(),
       provider = provider?.redacted(),
       profile = profile == null ? null : sanitizeAuthPublicAttributes(profile),
       super();

  final EngineContext context;
  final AuthAccount account;
  final AuthUser? user;
  final AuthProvider? provider;
  final Map<String, dynamic>? profile;
}

/// Event emitted when a session payload is produced.
final class AuthSessionEvent extends Event {
  AuthSessionEvent({
    required this.context,
    required AuthSession session,
    required Map<String, dynamic> payload,
    required this.strategy,
    AuthProvider? provider,
  }) : session = session.redacted(),
       provider = provider?.redacted(),
       payload = sanitizeAuthPublicAttributes(payload),
       super();

  final EngineContext context;
  final AuthSession session;
  final Map<String, dynamic> payload;
  final AuthSessionStrategy strategy;
  final AuthProvider? provider;
}
