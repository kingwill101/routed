import 'dart:async';
import 'dart:io';

import 'package:server_auth/server_auth.dart'
    show
        AuthSessionRuntimeAdapter,
        AuthGuard,
        AuthGuardRegistry,
        AuthGuardService,
        AuthPrincipal,
        RememberSessionAuthRuntime,
        buildExpiredRememberTokenCookie,
        buildRememberTokenCookie,
        buildBearerAuthenticateHeader,
        requireAuthenticatedGuard,
        requireRolesGuard,
        RememberTokenStore,
        InMemoryRememberTokenStore;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';

/// Key for storing the authenticated principal in the session.
const String _sessionPrincipalKey = '__routed.auth.principal';

/// Default name for the "remember me" cookie.
const String _defaultRememberCookieName = 'remember_token';

class SessionAuthService {
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
       );

  final RememberSessionAuthRuntime<EngineContext> _runtime;

  RememberTokenStore get rememberStore => _runtime.rememberStore;

  String get rememberCookieName => _runtime.rememberCookieName;

  Duration get defaultRememberDuration => _runtime.defaultRememberDuration;

  /// Logs in the user by storing their [AuthPrincipal] in the session.
  ///
  /// - [ctx]: The current [EngineContext].
  /// - [principal]: The authenticated principal to store.
  /// - [rememberMe]: Whether to enable "remember me" functionality.
  /// - [rememberDuration]: The duration for which the "remember me" token is valid.
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

  Future<void> logout(EngineContext ctx) async {
    await _runtime.logout(ctx);
  }

  AuthPrincipal? current(EngineContext ctx) {
    return _runtime.current(ctx);
  }

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
      secure: options.secure == true,
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
      secure: options.secure == true,
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

class SessionAuth {
  SessionAuth._internal();

  static SessionAuthService _service = SessionAuthService();

  static SessionAuthService get instance => _service;

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
    _service = service;
    return _service;
  }

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

  static Future<void> logout(EngineContext ctx) {
    return _service.logout(ctx);
  }

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
  /// When no updater has been wired (e.g. a minimal setup without
  /// [AuthServiceProvider]), the method falls back to
  /// [SessionAuth.login], which replaces the session principal directly.
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
    return _service.login(ctx, principal);
  }

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
