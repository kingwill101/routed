import 'package:server_auth/server_auth.dart'
    show
        AuthAccount,
        AuthSession,
        AuthSessionStrategy,
        AuthUser,
        AuthCredentials,
        AuthProvider;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/events/event.dart';

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
