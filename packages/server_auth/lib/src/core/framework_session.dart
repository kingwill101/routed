import 'dart:async';

/// A framework adapter hook invoked during authentication sign-out.
///
/// The auth core does not know how a host stores its framework session or
/// emits its cookie. Adapters can use these hooks to synchronize that state
/// without making the auth manager depend on a particular HTTP framework.
typedef AuthFrameworkSessionHook<TContext> =
    FutureOr<void> Function(TContext context);

/// Lifecycle hooks for a framework-owned session surrounding sign-out.
///
/// [beforeSignOut] runs after the current auth session has been resolved but
/// before auth records are revoked. [afterSignOut] runs after the auth
/// principal has been cleared and any requested framework-session destruction
/// has been applied. The latter is the appropriate place to expire a host
/// session cookie or commit an equivalent response mutation.
final class AuthFrameworkSessionHooks<TContext> {
  /// Creates optional hooks for the framework session sign-out lifecycle.
  const AuthFrameworkSessionHooks({this.beforeSignOut, this.afterSignOut});

  /// Hook invoked before auth records are revoked.
  final AuthFrameworkSessionHook<TContext>? beforeSignOut;

  /// Hook invoked after the auth principal and framework session are cleared.
  final AuthFrameworkSessionHook<TContext>? afterSignOut;

  /// Whether neither lifecycle hook was supplied.
  bool get isEmpty => beforeSignOut == null && afterSignOut == null;
}
