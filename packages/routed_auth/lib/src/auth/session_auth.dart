import 'dart:async';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart'
    show AuthManager, AuthServiceProvider;
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_auth/server_auth.dart'
    show
        AuthGuard,
        AuthGuardRegistry,
        AuthGuardService,
        AuthPrincipal,
        AuthSessionRuntimeAdapter,
        InMemoryRememberTokenStore,
        RememberSessionAuthRuntime,
        RememberTokenStore,
        buildBearerAuthenticateHeader,
        buildExpiredRememberTokenCookie,
        buildRememberTokenCookie,
        requireAuthenticatedGuard,
        requireRolesGuard;

/// Key for storing the authenticated principal in the session.
const String _sessionPrincipalKey = '__routed.auth.principal';

/// Default name for the "remember me" cookie.
const String _defaultRememberCookieName = 'remember_token';

/// Routed adapter for session and remember-me authentication.
class SessionAuthService {
  /// Creates a service with optional remember-token storage and cookie settings.
  ///
  /// Defaults to an in-memory store, the `remember_token` cookie, a 30-day
  /// remember duration, and session rotation during login.
  SessionAuthService({
    RememberTokenStore? rememberStore,
    String rememberCookieName = _defaultRememberCookieName,
    Duration defaultRememberDuration = const Duration(days: 30),
  }) : _runtime = RememberSessionAuthRuntime<EngineContext>(
         adapter: const _RoutedAuthSessionRuntimeAdapter(),
         rememberStore: rememberStore ?? InMemoryRememberTokenStore(),
         rememberCookieName: rememberCookieName,
         defaultRememberDuration: defaultRememberDuration,
         sessionPrincipalKey: _sessionPrincipalKey,
         regenerateSession: (context) => context.session.regenerate(),
       );

  final RememberSessionAuthRuntime<EngineContext> _runtime;

  /// Effective remember-token store used by this service.
  RememberTokenStore get rememberStore => _runtime.rememberStore;

  /// Effective name of the remember-me cookie.
  String get rememberCookieName => _runtime.rememberCookieName;

  /// Effective lifetime assigned to rotated remember tokens.
  Duration get defaultRememberDuration => _runtime.defaultRememberDuration;

  /// Logs in [principal] and stores it in the current session.
  ///
  ///
  /// When [rememberMe] is true, saves a remember token for [rememberDuration]
  /// or the configured default. The session is rotated before writing by
  /// default. Blank principal IDs and non-positive remember durations throw an
  /// [ArgumentError].
  ///
  /// Example:
  /// ```dart
  /// final principal = AuthPrincipal(id: 'user123', roles: ['admin']);
  /// await sessionAuthService.login(ctx, principal, rememberMe: true);
  /// ```
  Future<void> login(
    EngineContext ctx,
    AuthPrincipal principal, {
    bool rememberMe = false,
    Duration? rememberDuration,
  }) async {
    await _runtime.login(
      ctx,
      principal,
      rememberMe: rememberMe,
      rememberDuration: rememberDuration,
    );
  }

  /// Updates [principal] without rotating the current session.
  Future<void> update(EngineContext ctx, AuthPrincipal principal) async {
    await _runtime.login(ctx, principal, rotateSession: false);
  }

  /// Logs out the current request and expires its remember-me cookie.
  Future<void> logout(EngineContext ctx) async {
    await _runtime.logout(ctx);
  }

  /// Returns the current request principal, or null when unauthenticated.
  AuthPrincipal? current(EngineContext ctx) {
    return _runtime.current(ctx);
  }

  /// Creates middleware that hydrates authentication before `next` runs.
  ///
  /// Install this after `sessionMiddleware()` so the routed session is
  /// available to the adapter.
  Middleware middleware() {
    return (EngineContext ctx, Next next) async {
      await _runtime.hydrate(ctx);
      return await next();
    };
  }
}

class _RoutedAuthSessionRuntimeAdapter
    implements AuthSessionRuntimeAdapter<EngineContext> {
  const _RoutedAuthSessionRuntimeAdapter();

  @override
  Cookie buildExpiredRememberCookie(EngineContext context, String cookieName) {
    final options = context.session.options;
    return buildExpiredRememberTokenCookie(
      cookieName,
      path: options.path ?? '/',
      domain: options.domain,
      secure: options.secure ?? false,
      sameSite: options.sameSite,
    );
  }

  @override
  Cookie buildRememberCookie(
    EngineContext context,
    String cookieName,
    String token,
    DateTime expiresAt,
  ) {
    final options = context.session.options;
    return buildRememberTokenCookie(
      cookieName,
      token,
      expiresAt: expiresAt,
      path: options.path ?? '/',
      domain: options.domain,
      secure: options.secure ?? false,
      sameSite: options.sameSite,
    );
  }

  @override
  AuthPrincipal? readPrincipalAttribute(
    EngineContext context,
    String attributeKey,
  ) {
    return context.request.getAttribute<AuthPrincipal?>(attributeKey);
  }

  @override
  Map<String, dynamic>? readSessionPrincipal(
    EngineContext context,
    String sessionKey,
  ) {
    return context.session.getValue<Map<String, dynamic>>(sessionKey);
  }

  @override
  Iterable<Cookie> requestCookies(EngineContext context) {
    return context.request.cookies;
  }

  @override
  void setResponseCookie(EngineContext context, Cookie cookie) {
    context.response.cookies.add(cookie);
  }

  @override
  void writePrincipalAttribute(
    EngineContext context,
    String attributeKey,
    AuthPrincipal? principal,
  ) {
    context.request.setAttribute(attributeKey, principal);
  }

  @override
  void writeSessionPrincipal(
    EngineContext context,
    String sessionKey,
    Map<String, dynamic>? principalJson,
  ) {
    if (principalJson == null) {
      context.session.values.remove(sessionKey);
      return;
    }
    context.session.setValue(sessionKey, principalJson);
  }
}

/// Process-global facade for the configured [SessionAuthService].
class SessionAuth {
  SessionAuth._internal();

  static SessionAuthService _service = SessionAuthService();

  /// Current process-wide session authentication service.
  static SessionAuthService get instance => _service;

  /// Replaces the process-wide service, preserving omitted current settings.
  ///
  /// Middleware and guards already created retain the service instance they
  /// captured; configure them again when changing authentication settings.
  static SessionAuthService configure({
    RememberTokenStore? rememberStore,
    String? rememberCookieName,
    Duration? defaultRememberDuration,
  }) {
    final current = _service;
    final service = SessionAuthService(
      rememberStore: rememberStore ?? current.rememberStore,
      rememberCookieName: rememberCookieName ?? current.rememberCookieName,
      defaultRememberDuration:
          defaultRememberDuration ?? current.defaultRememberDuration,
    );
    return _service = service;
  }

  /// Delegates login to [instance], rotating the session by default.
  static Future<void> login(
    EngineContext ctx,
    AuthPrincipal principal, {
    bool rememberMe = false,
    Duration? rememberDuration,
  }) {
    return _service.login(
      ctx,
      principal,
      rememberMe: rememberMe,
      rememberDuration: rememberDuration,
    );
  }

  /// Delegates logout to [instance] and expires the remember cookie.
  static Future<void> logout(EngineContext ctx) {
    return _service.logout(ctx);
  }

  /// Returns the principal resolved by [instance] for [ctx].
  static AuthPrincipal? current(EngineContext ctx) {
    return _service.current(ctx);
  }

  /// Callback wired by [AuthServiceProvider] when it creates an
  /// [AuthManager].  When set, [updateSession] delegates to it so that
  /// both server-side sessions and JWT cookies are handled transparently.
  static Future<void> Function(EngineContext ctx, AuthPrincipal principal)?
  _sessionUpdater;

  /// Registers the strategy-aware session updater.
  ///
  /// Called by [AuthServiceProvider] during setup — application code should
  /// not need to call this directly.
  static void setSessionUpdater(
    Future<void> Function(EngineContext ctx, AuthPrincipal principal)? updater,
  ) {
    _sessionUpdater = updater;
  }

  /// Updates the current auth session with the given [principal].
  ///
  /// This is the recommended way to refresh the authenticated identity after
  /// changing user attributes, roles, or other profile data that should be
  /// reflected in the session immediately.
  ///
  /// When [AuthServiceProvider] has booted, the call is delegated to
  /// [AuthManager.updateSession] — handling both server-side sessions
  /// **and** JWT reissuance transparently.
  ///
  /// When no updater has been wired (for example, without
  /// [AuthServiceProvider]), the method performs a session-only, non-rotating
  /// update through the configured service.
  ///
  /// ## Example
  ///
  /// ```dart
  /// engine.post('/update-profile', (ctx) async {
  ///   final principal = SessionAuth.current(ctx)!;
  ///   final updated = AuthPrincipal(
  ///     id: principal.id,
  ///     roles: principal.roles,
  ///     attributes: {...principal.attributes, 'theme': 'dark'},
  ///   );
  ///   await SessionAuth.updateSession(ctx, updated);
  ///   return ctx.json({'ok': true});
  /// });
  /// ```
  static Future<void> updateSession(
    EngineContext ctx,
    AuthPrincipal principal,
  ) async {
    final updater = _sessionUpdater;
    if (updater != null) {
      return updater(ctx, principal);
    }
    // No strategy-aware updater wired — session-only fallback.
    return _service.update(ctx, principal);
  }

  /// Creates middleware that hydrates sessions using the configured service.
  ///
  /// Non-null options first call [configure], preserving omitted settings.
  /// Install the returned middleware after `sessionMiddleware()`.
  static Middleware sessionAuthMiddleware({
    RememberTokenStore? rememberStore,
    String? rememberCookieName,
    Duration? defaultRememberDuration,
  }) {
    if (rememberStore != null ||
        rememberCookieName != null ||
        defaultRememberDuration != null) {
      configure(
        rememberStore: rememberStore,
        rememberCookieName: rememberCookieName,
        defaultRememberDuration: defaultRememberDuration,
      );
    }
    return _service.middleware();
  }
}

/// Global guard registry used by [guardMiddleware].
final AuthGuardRegistry<EngineContext, Response> guardRegistry =
    AuthGuardRegistry<EngineContext, Response>();

/// Global guard service used by [guardMiddleware].
final AuthGuardService<EngineContext, Response> guardService =
    AuthGuardService<EngineContext, Response>(registry: guardRegistry);

/// Creates middleware that evaluates registered guards in order.
///
/// The first denial is returned unchanged. A denial without a response becomes
/// HTTP 403 with a generic message; allowed requests continue to `next`.
Middleware guardMiddleware(
  List<String> guardNames, {
  AuthGuardRegistry<EngineContext, Response>? registry,
}) {
  final service = registry == null
      ? guardService
      : AuthGuardService<EngineContext, Response>(registry: registry);

  return (EngineContext ctx, Next next) async {
    final denied = await service.firstDenied(
      guardNames,
      ctx,
      onDenied: (context, name) {
        context.response.statusCode = HttpStatus.forbidden;
        context.response.write('Forbidden by guard: $name');
        return context.response;
      },
    );
    if (denied != null) {
      return denied;
    }
    return await next();
  };
}

/// Creates a guard that requires a principal for the selected service.
///
/// Denied requests receive HTTP 401, an appropriate Bearer challenge using
/// [realm], and `Authentication required`. The service is captured when the
/// guard is created.
AuthGuard<EngineContext, Response> requireAuthenticated({
  String realm = 'Restricted',
  SessionAuthService? sessionAuth,
}) {
  final auth = sessionAuth ?? SessionAuth.instance;
  return requireAuthenticatedGuard<EngineContext, Response>(
    principalResolver: auth.current,
    onDenied: (ctx) {
      ctx.response.statusCode = HttpStatus.unauthorized;
      ctx.response.headers.set(
        'WWW-Authenticate',
        buildBearerAuthenticateHeader(realm: realm),
      );
      ctx.response.write('Authentication required');
      return ctx.response;
    },
  );
}

/// Creates a guard that checks roles on the selected service's principal.
///
/// Blank role names are ignored. With [any] false every remaining role is
/// required; with true at least one is required. An empty expected list allows
/// any authenticated principal. The selected service is captured at creation.
AuthGuard<EngineContext, Response> requireRoles(
  List<String> roles, {
  SessionAuthService? sessionAuth,
  bool any = false,
}) {
  final expected = roles
      .map((role) => role.trim())
      .where((role) => role.isNotEmpty)
      .toList(growable: false);

  final auth = sessionAuth ?? SessionAuth.instance;

  return requireRolesGuard<EngineContext, Response>(
    expected,
    principalResolver: auth.current,
    any: any,
    onUnauthenticated: (ctx) {
      ctx.response.statusCode = HttpStatus.unauthorized;
      ctx.response.write('Authentication required');
      return ctx.response;
    },
  );
}
