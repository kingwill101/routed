import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed/src/support/named_registry.dart';

const String authPrincipalAttribute = 'auth.principal';
const String _sessionPrincipalKey = '__routed.auth.principal';
const String _defaultRememberCookieName = 'remember_token';

class AuthPrincipal {
  AuthPrincipal({
    required this.id,
    this.roles = const <String>[],
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? const <String, dynamic>{}
           : Map<String, dynamic>.from(attributes);

  final String id;
  final List<String> roles;
  final Map<String, dynamic> attributes;

  bool hasRole(String role) => roles.contains(role);

  Map<String, dynamic> toJson() => {
    'id': id,
    'roles': roles,
    'attributes': attributes,
  };

  factory AuthPrincipal.fromJson(Map<String, dynamic> json) {
    return AuthPrincipal(
      id: json['id'] as String,
      roles: (json['roles'] as List?)?.cast<String>() ?? const <String>[],
      attributes: (json['attributes'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

abstract class RememberTokenStore {
  FutureOr<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  );

  FutureOr<AuthPrincipal?> read(String token);

  FutureOr<void> remove(String token);
}

class InMemoryRememberTokenStore implements RememberTokenStore {
  final Map<String, _RememberRecord> _storage = <String, _RememberRecord>{};

  @override
  Future<void> save(
    String token,
    AuthPrincipal principal,
    DateTime expiresAt,
  ) async {
    _storage[token] = _RememberRecord(principal, expiresAt);
  }

  @override
  Future<AuthPrincipal?> read(String token) async {
    final record = _storage[token];
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      _storage.remove(token);
      return null;
    }
    return record.principal;
  }

  @override
  Future<void> remove(String token) async {
    _storage.remove(token);
  }
}

class _RememberRecord {
  _RememberRecord(this.principal, this.expiresAt);

  final AuthPrincipal principal;
  final DateTime expiresAt;
}

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

class GuardResult {
  const GuardResult._(this.allowed, this.response);

  final bool allowed;
  final Response? response;

  static GuardResult allow() => const GuardResult._(true, null);

  static GuardResult deny([Response? response]) =>
      GuardResult._(false, response);
}

typedef AuthGuard = FutureOr<GuardResult> Function(EngineContext ctx);

class GuardRegistry extends NamedRegistry<AuthGuard> {
  GuardRegistry._();

  static final GuardRegistry instance = GuardRegistry._();

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
      return GuardResult.allow();
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
      return GuardResult.allow();
    }

    final matches = any
        ? expected.any(principal.hasRole)
        : expected.every(principal.hasRole);
    return matches ? GuardResult.allow() : GuardResult.deny();
  };
}

String _generateToken() {
  final rand = Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64UrlEncode(bytes);
}
