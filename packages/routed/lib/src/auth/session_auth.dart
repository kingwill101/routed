import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:server_auth/server_auth.dart'
    show
        AuthPrincipal,
        RememberTokenStore,
        InMemoryRememberTokenStore,
        authPrincipalAttribute;
import 'package:server_auth/server_auth.dart'
    as server_auth
    show AuthGuard, GuardResult;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';
import 'package:server_data/sessions.dart';
import 'package:routed/src/support/named_registry.dart';

/// Key for storing the authenticated principal in the session.
const String _sessionPrincipalKey = '__routed.auth.principal';

/// Default name for the "remember me" cookie.
const String _defaultRememberCookieName = 'remember_token';

class SessionAuthService {
  SessionAuthService({
    RememberTokenStore? rememberStore,
    String rememberCookieName = _defaultRememberCookieName,
    Duration defaultRememberDuration = const Duration(days: 30),
  }) : _rememberStore = rememberStore ?? InMemoryRememberTokenStore(),
       _rememberCookieName = rememberCookieName,
       _defaultRememberDuration = defaultRememberDuration;

  final RememberTokenStore _rememberStore;
  final String _rememberCookieName;
  final Duration _defaultRememberDuration;

  RememberTokenStore get rememberStore => _rememberStore;

  String get rememberCookieName => _rememberCookieName;

  Duration get defaultRememberDuration => _defaultRememberDuration;

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
    ctx.session.setValue(_sessionPrincipalKey, principal.toJson());
    ctx.request.setAttribute(authPrincipalAttribute, principal);

    if (!rememberMe) {
      return;
    }

    final existing = _findRequestCookie(ctx);
    if (existing != null && existing.value.isNotEmpty) {
      await Future.sync(() => _rememberStore.remove(existing.value));
    }

    final token = _generateToken();
    final expiresAt = DateTime.now().add(
      rememberDuration ?? _defaultRememberDuration,
    );
    await Future.sync(() => _rememberStore.save(token, principal, expiresAt));
    ctx.response.cookies.add(_buildCookie(ctx.session, token, expiresAt));
  }

  Future<void> logout(EngineContext ctx) async {
    ctx.session.values.remove(_sessionPrincipalKey);
    ctx.request.setAttribute(authPrincipalAttribute, null);

    final cookie = _findRequestCookie(ctx);
    if (cookie != null && cookie.value.isNotEmpty) {
      await Future.sync(() => _rememberStore.remove(cookie.value));
    }
    ctx.response.cookies.add(_expiredCookie(ctx.session));
  }

  AuthPrincipal? current(EngineContext ctx) {
    final cached = ctx.request.getAttribute<AuthPrincipal?>(
      authPrincipalAttribute,
    );
    if (cached != null) {
      return cached;
    }

    final stored = ctx.session.getValue<Map<String, dynamic>>(
      _sessionPrincipalKey,
    );
    if (stored == null) {
      return null;
    }

    final principal = AuthPrincipal.fromJson(stored);
    ctx.request.setAttribute(authPrincipalAttribute, principal);
    return principal;
  }

  Middleware middleware() {
    return (EngineContext ctx, Next next) async {
      final sessionData = ctx.session.getValue<Map<String, dynamic>>(
        _sessionPrincipalKey,
      );
      if (sessionData != null) {
        ctx.request.setAttribute(
          authPrincipalAttribute,
          AuthPrincipal.fromJson(sessionData),
        );
        return await next();
      }

      final rememberCookie = _findRequestCookie(ctx);
      if (rememberCookie == null || rememberCookie.value.isEmpty) {
        return await next();
      }

      final principal = await Future.sync(
        () => _rememberStore.read(rememberCookie.value),
      );
      if (principal == null) {
        await Future.sync(() => _rememberStore.remove(rememberCookie.value));
        ctx.response.cookies.add(_expiredCookie(ctx.session));
        return await next();
      }

      ctx.session.setValue(_sessionPrincipalKey, principal.toJson());
      ctx.request.setAttribute(authPrincipalAttribute, principal);

      final rotatedToken = _generateToken();
      final newExpiry = DateTime.now().add(_defaultRememberDuration);
      await Future.sync(
        () => _rememberStore.save(rotatedToken, principal, newExpiry),
      );
      await Future.sync(() => _rememberStore.remove(rememberCookie.value));
      ctx.response.cookies.add(
        _buildCookie(ctx.session, rotatedToken, newExpiry),
      );

      return await next();
    };
  }

  Cookie? _findRequestCookie(EngineContext ctx) {
    for (final cookie in ctx.request.cookies) {
      if (cookie.name == _rememberCookieName) {
        return cookie;
      }
    }
    return null;
  }

  Cookie _buildCookie(Session session, String value, DateTime expiresAt) {
    final cookie = Cookie(_rememberCookieName, value)
      ..httpOnly = true
      ..expires = expiresAt;

    final options = session.options;
    cookie.path = options.path ?? '/';
    if (options.domain != null && options.domain!.isNotEmpty) {
      cookie.domain = options.domain!;
    }
    if (options.secure == true) {
      cookie.secure = true;
    }
    if (options.sameSite != null) {
      cookie.sameSite = options.sameSite!;
    }

    return cookie;
  }

  Cookie _expiredCookie(Session session) {
    final cookie = _buildCookie(
      session,
      '',
      DateTime.fromMillisecondsSinceEpoch(0),
    );
    cookie.maxAge = 0;
    return cookie;
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

typedef GuardResult = server_auth.GuardResult<Response>;
typedef AuthGuard = server_auth.AuthGuard<EngineContext, Response>;

class GuardRegistry extends NamedRegistry<AuthGuard> {
  GuardRegistry._();

  static final GuardRegistry instance = GuardRegistry._();

  @override
  String normalizeName(String name) => name.trim();

  void register(String name, AuthGuard handler) {
    registerEntry(name, handler);
  }

  void unregister(String name) {
    unregisterEntry(name);
  }

  AuthGuard? resolve(String name) => getEntry(name);

  Iterable<String> get names => entryNames;
}

Middleware guardMiddleware(List<String> guardNames, {GuardRegistry? registry}) {
  final reg = registry ?? GuardRegistry.instance;
  return (EngineContext ctx, Next next) async {
    for (final name in guardNames) {
      final handler = reg.resolve(name);
      if (handler == null) {
        continue;
      }
      final result = await Future.sync(() => handler(ctx));
      if (!result.allowed) {
        if (result.response != null) {
          return result.response!;
        }
        ctx.response.statusCode = HttpStatus.forbidden;
        ctx.response.write('Forbidden by guard: $name');
        return ctx.response;
      }
    }
    return await next();
  };
}

AuthGuard requireAuthenticated({
  String realm = 'Restricted',
  SessionAuthService? sessionAuth,
}) {
  final auth = sessionAuth ?? SessionAuth.instance;
  return (EngineContext ctx) {
    final principal = auth.current(ctx);
    if (principal != null) {
      return const GuardResult.allow();
    }
    ctx.response.statusCode = HttpStatus.unauthorized;
    ctx.response.headers.set('WWW-Authenticate', 'Bearer realm="$realm"');
    ctx.response.write('Authentication required');
    return GuardResult.deny(ctx.response);
  };
}

AuthGuard requireRoles(
  List<String> roles, {
  SessionAuthService? sessionAuth,
  bool any = false,
}) {
  final expected = roles
      .map((role) => role.trim())
      .where((role) => role.isNotEmpty)
      .toList(growable: false);

  final auth = sessionAuth ?? SessionAuth.instance;

  return (EngineContext ctx) {
    final principal = auth.current(ctx);
    if (principal == null) {
      ctx.response.statusCode = HttpStatus.unauthorized;
      ctx.response.write('Authentication required');
      return GuardResult.deny(ctx.response);
    }

    if (expected.isEmpty) {
      return const GuardResult.allow();
    }

    final matches = any
        ? expected.any(principal.hasRole)
        : expected.every(principal.hasRole);
    return matches ? const GuardResult.allow() : const GuardResult.deny();
  };
}

String _generateToken() {
  final rand = Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64UrlEncode(bytes);
}
