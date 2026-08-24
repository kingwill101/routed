// ignore_for_file: implementation_imports
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/events/event.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthAccount,
        AuthCredentials,
        AuthProvider,
        AuthSession,
        AuthSessionStrategy,
        AuthUser,
        sanitizeAuthPublicAttributes;

const _authEventMetadataMaxLength = 256;
const _authEventPathMaxLength = 2048;

String _boundAuthEventMetadata(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return value.substring(0, maxLength);
}

/// An immutable, bounded request-metadata projection for authentication events.
///
/// This type intentionally does not retain the originating [EngineContext] or
/// expose request headers, cookies, query parameters, body, response, engine,
/// container, or host context. Client IP is also omitted because it can be
/// personal data and may be derived from proxy-controlled headers.
final class AuthEventContext {
  /// Creates a safe event context from bounded request metadata.
  factory AuthEventContext({
    required String requestId,
    required String method,
    required String path,
    required String host,
    required String scheme,
  }) {
    return AuthEventContext._(
      requestId: _boundAuthEventMetadata(
        requestId,
        _authEventMetadataMaxLength,
      ),
      method: _boundAuthEventMetadata(method, _authEventMetadataMaxLength),
      path: _boundAuthEventMetadata(path, _authEventPathMaxLength),
      host: _boundAuthEventMetadata(host, _authEventMetadataMaxLength),
      scheme: _boundAuthEventMetadata(scheme, _authEventMetadataMaxLength),
    );
  }

  /// Projects safe metadata from [context] without retaining [context].
  factory AuthEventContext.from(EngineContext context) {
    return AuthEventContext(
      requestId: context.id,
      method: context.method,
      path: context.path,
      host: context.host,
      scheme: context.scheme,
    );
  }

  const AuthEventContext._({
    required this.requestId,
    required this.method,
    required this.path,
    required this.host,
    required this.scheme,
  });

  /// The bounded request identifier assigned by the host.
  final String requestId;

  /// The bounded HTTP method.
  final String method;

  /// The bounded origin-relative path, without query parameters.
  final String path;

  /// The bounded request host.
  final String host;

  /// The bounded request scheme.
  final String scheme;
}

/// Event emitted after a successful sign-in.
///
/// Authentication model fields are redacted before the event is published;
/// credentials, provider secrets, account tokens, JWTs, and nested
/// secret-like values must not escape into event listeners or audit pipelines.
final class AuthSignInEvent extends Event {
  /// Creates a sign-in event from sanitized authentication snapshots.
  ///
  /// [user], [session], [provider], [account], and [credentials] are redacted,
  /// while [profile] is recursively sanitized before publication. [redirectUrl]
  /// is the optional post-sign-in destination, and [isNewUser] identifies a
  /// user created during this sign-in flow.
  AuthSignInEvent({
    required EngineContext context,
    required AuthUser user,
    required this.strategy,
    required AuthSession session,
    AuthProvider? provider,
    AuthAccount? account,
    Map<String, dynamic>? profile,
    AuthCredentials? credentials,
    this.redirectUrl,
    this.isNewUser = false,
  }) : context = AuthEventContext.from(context),
       user = user.redacted(),
       session = session.redacted(),
       provider = provider?.redacted(),
       credentials = credentials?.redacted(),
       account = account?.redacted(),
       profile = profile == null ? null : sanitizeAuthPublicAttributes(profile),
       super();

  /// Safe request metadata from the context in which sign-in completed.
  final AuthEventContext context;

  /// The redacted signed-in user snapshot.
  final AuthUser user;

  /// The redacted session created or resumed by sign-in.
  final AuthSession session;

  /// The authentication strategy used for sign-in.
  final AuthSessionStrategy strategy;

  /// The optional redacted provider involved in sign-in.
  final AuthProvider? provider;

  /// The optional redacted provider account involved in sign-in.
  final AuthAccount? account;

  /// The optional recursively sanitized provider profile.
  final Map<String, dynamic>? profile;

  /// The optional redacted credentials used by sign-in.
  final AuthCredentials? credentials;

  /// The optional destination requested after sign-in.
  final String? redirectUrl;

  /// Whether sign-in created a new user.
  final bool isNewUser;
}

/// Event emitted after a sign-out flow completes.
final class AuthSignOutEvent extends Event {
  /// Creates a sign-out event with redacted optional authentication snapshots.
  AuthSignOutEvent({
    required EngineContext context,
    required this.strategy,
    AuthSession? session,
    AuthUser? user,
  }) : context = AuthEventContext.from(context),
       session = session?.redacted(),
       user = user?.redacted(),
       super();

  /// Safe request metadata from the context in which sign-out completed.
  final AuthEventContext context;

  /// The authentication strategy used for sign-out.
  final AuthSessionStrategy strategy;

  /// The optional redacted session being terminated.
  final AuthSession? session;

  /// The optional redacted user signing out.
  final AuthUser? user;
}

/// Event emitted when a new user is created.
final class AuthCreateUserEvent extends Event {
  /// Creates a user-creation event with redacted and sanitized snapshots.
  AuthCreateUserEvent({
    required EngineContext context,
    required AuthUser user,
    AuthProvider? provider,
    Map<String, dynamic>? profile,
  }) : context = AuthEventContext.from(context),
       user = user.redacted(),
       provider = provider?.redacted(),
       profile = profile == null ? null : sanitizeAuthPublicAttributes(profile),
       super();

  /// Safe request metadata from the context in which the user was created.
  final AuthEventContext context;

  /// The redacted newly created user snapshot.
  final AuthUser user;

  /// The optional redacted provider associated with the user.
  final AuthProvider? provider;

  /// The optional recursively sanitized provider profile.
  final Map<String, dynamic>? profile;
}

/// Event emitted when a user is updated.
final class AuthUpdateUserEvent extends Event {
  /// Creates a user-update event with redacted authentication snapshots.
  AuthUpdateUserEvent({
    required EngineContext context,
    required AuthUser user,
    AuthProvider? provider,
  }) : context = AuthEventContext.from(context),
       user = user.redacted(),
       provider = provider?.redacted(),
       super();

  /// Safe request metadata from the context in which the user was updated.
  final AuthEventContext context;

  /// The redacted updated user snapshot.
  final AuthUser user;

  /// The optional redacted provider associated with the update.
  final AuthProvider? provider;
}

/// Event emitted when a provider account is linked.
final class AuthLinkAccountEvent extends Event {
  /// Creates an account-link event with redacted and sanitized snapshots.
  AuthLinkAccountEvent({
    required EngineContext context,
    required AuthAccount account,
    AuthUser? user,
    AuthProvider? provider,
    Map<String, dynamic>? profile,
  }) : context = AuthEventContext.from(context),
       account = account.redacted(),
       user = user?.redacted(),
       provider = provider?.redacted(),
       profile = profile == null ? null : sanitizeAuthPublicAttributes(profile),
       super();

  /// Safe request metadata from the context in which the account was linked.
  final AuthEventContext context;

  /// The redacted provider account that was linked.
  final AuthAccount account;

  /// The optional redacted user receiving the linked account.
  final AuthUser? user;

  /// The optional redacted provider for the linked account.
  final AuthProvider? provider;

  /// The optional recursively sanitized provider profile.
  final Map<String, dynamic>? profile;
}

/// Event emitted when a session payload is produced.
final class AuthSessionEvent extends Event {
  /// Creates a session event with redacted and sanitized snapshots.
  AuthSessionEvent({
    required EngineContext context,
    required AuthSession session,
    required Map<String, dynamic> payload,
    required this.strategy,
    AuthProvider? provider,
  }) : context = AuthEventContext.from(context),
       session = session.redacted(),
       provider = provider?.redacted(),
       payload = sanitizeAuthPublicAttributes(payload),
       super();

  /// Safe request metadata from the context in which the payload was produced.
  final AuthEventContext context;

  /// The redacted session represented by the payload.
  final AuthSession session;

  /// The recursively sanitized payload exposed to listeners.
  final Map<String, dynamic> payload;

  /// The authentication strategy associated with the session.
  final AuthSessionStrategy strategy;

  /// The optional redacted provider associated with the session.
  final AuthProvider? provider;
}
