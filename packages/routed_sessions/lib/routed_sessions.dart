/// Session middleware and [EngineContext] helpers for Routed applications.
///
/// This library re-exports [Session], [SessionStore], and the built-in stores
/// from `server_sessions` and adds request lifecycle integration.
library;

import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/src/config.dart';
import 'package:server_sessions/server_sessions.dart';

export 'package:server_sessions/server_sessions.dart';

export 'src/config.dart';

/// Context key used by [sessionMiddleware] to store the current session.
const sessionKey = ContextKey<Session>('routed.session');

/// Convenience accessors for the session attached to an [EngineContext].
extension SessionEngineContext on EngineContext {
  /// Returns the current session.
  ///
  /// Throws a [StateError] when [sessionMiddleware] has not run for this
  /// request.
  Session get session {
    final s = get<Session>(sessionKey.name);
    if (s == null) throw StateError('Session middleware not configured');
    return s;
  }

  /// Whether [sessionMiddleware] attached a session to this context.
  bool get hasSession => get<Session>(sessionKey.name) != null;

  /// Returns the typed value stored under [key], or `null` when unavailable.
  T? getSession<T>(String key) {
    try {
      return session.getValue<T>(key);
    } on Object catch (_) {
      return null;
    }
  }

  /// Stores [value] under [key] when a session is available.
  void setSession(String key, dynamic value) {
    try {
      session.setValue(key, value);
    } on Object catch (_) {}
  }

  /// Removes the value stored under [key].
  void removeSession(String key) => session.values.remove(key);

  /// Removes all values from the current session.
  void clearSession() => session.values.clear();

  /// Whether the current session contains [key].
  bool hasSessionKey(String key) => session.values.containsKey(key);

  /// A copy of the current session data.
  Map<String, dynamic> get sessionData => Map.from(session.values);

  /// The current session identifier.
  String get sessionId => session.id;

  /// Destroys the current session and expires it when written.
  void destroySession() => session.destroy();

  /// Adds a one-time flash [message] under [category].
  void flash(String message, [String category = 'message']) {
    try {
      final existing = session.values['_flash'];
      final List<Map<String, String>> list;
      if (existing is List) {
        list = existing.map((e) => Map<String, String>.from(e as Map)).toList();
      } else {
        list = <Map<String, String>>[];
      }
      list.add({'message': message, 'category': category});
      session.values['_flash'] = list;
    } on Object catch (_) {}
  }

  /// Whether the current session contains flash messages.
  bool hasFlashMessages() {
    try {
      final flashes = session.values['_flash'] as List?;
      return flashes != null && flashes.isNotEmpty;
    } on Object catch (_) {
      return false;
    }
  }

  /// Returns and removes flash messages from the current session.
  ///
  /// When [withCategories] is true, each item is `[category, message]`;
  /// otherwise each item is the message string. [categoryFilter] limits the
  /// returned messages without changing the one-time removal behavior.
  List<dynamic> getFlashMessages({
    bool withCategories = false,
    List<String>? categoryFilter,
  }) {
    try {
      final flashes = session.values['_flash'];
      if (flashes is! List || flashes.isEmpty) return [];
      final source = flashes
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
      session.values.remove('_flash');
      var filtered = source;
      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        filtered = filtered
            .where((m) => categoryFilter.contains(m['category']))
            .toList();
      }
      if (withCategories) {
        return filtered.map((m) => [m['category'], m['message']]).toList();
      }
      return filtered.map((m) => m['message']!).toList();
    } on Object catch (_) {
      return [];
    }
  }
}

class _EngineSessionRequest implements SessionRequest {
  _EngineSessionRequest(this.ctx);
  final EngineContext ctx;
  @override
  List<Cookie> get cookies {
    try {
      return ctx.request.cookies;
    } on Object catch (_) {
      return const [];
    }
  }

  @override
  String header(String name) {
    try {
      final v = (ctx.request.headers as dynamic).value(name);
      if (v is String && v.isNotEmpty) return v;
      if (v is List && v.isNotEmpty) return v.first.toString();
    } on Object catch (_) {}
    try {
      final map = ctx.request.headers as Map<String, List<String>>;
      final values = map[name];
      if (values != null && values.isNotEmpty) return values.first;
      for (final entry in map.entries) {
        if (entry.key.toLowerCase() == name.toLowerCase() &&
            entry.value.isNotEmpty) {
          return entry.value.first;
        }
      }
    } on Object catch (_) {}
    try {
      final headers = ctx.request.headers;
      final v = headers.value(name);
      if (v != null) return v;
    } on Object catch (_) {}
    return '';
  }
}

class _EngineSessionResponse implements SessionResponse {
  _EngineSessionResponse(this.ctx);
  final EngineContext ctx;
  @override
  void setCookie(
    String name,
    dynamic value, {
    int? maxAge,
    String path = '/',
    String domain = '',
    bool secure = false,
    bool httpOnly = false,
    SameSite? sameSite,
  }) {
    try {
      ctx.response.setCookie(
        name,
        value?.toString() ?? '',
        maxAge: maxAge,
        path: path,
        domain: domain,
        secure: secure,
        httpOnly: httpOnly,
        sameSite: sameSite,
      );
    } on Object catch (_) {
      try {
        final sb = StringBuffer('$name=$value; Path=$path');
        if (maxAge != null) sb.write('; Max-Age=$maxAge');
        ctx.response.headers.set(HttpHeaders.setCookieHeader, sb.toString());
      } on Object catch (_) {}
    }
  }
}

/// Creates middleware that loads and persists a session for each request.
///
/// Uses [store] when supplied, then a configured [SessionConfig] or registered
/// [SessionStore]. If none is available, it falls back to a cookie store with
/// signed and encrypted cookies.
Middleware sessionMiddleware([SessionStore? store]) {
  return (EngineContext ctx, Next next) async {
    SessionConfig? config;
    var effectiveStore = store;
    var cookieName = 'routed_session';

    final container = ctx.container;
    if (container.has<SessionConfig>()) {
      config = container.get<SessionConfig>();
      cookieName = config.cookieName;
      effectiveStore ??= config.store;
    }
    if (effectiveStore == null && container.has<SessionStore>()) {
      effectiveStore = await container.make<SessionStore>();
    }

    if (effectiveStore == null) {
      // No explicit store: fall back to a cookie store derived from config or
      // the default.
      final opts = SessionOptions(
        secure: true,
        httpOnly: true,
        sameSite: SameSite.lax,
      );
      final configuredCodecs = config?.codecs ?? const <SecureCookie>[];
      final codecs = configuredCodecs.isNotEmpty
          ? configuredCodecs
          : [SecureCookie(useEncryption: true, useSigning: true)];
      effectiveStore = CookieStore(codecs: codecs, defaultOptions: opts);
      cookieName = config?.cookieName ?? cookieName;
    }

    final req = _EngineSessionRequest(ctx);
    final res = _EngineSessionResponse(ctx);

    // effectiveStore is now non-null after fallback.
    final resolvedStore = effectiveStore;
    Session session;
    try {
      session = await resolvedStore.read(req, cookieName);
    } on Object catch (_) {
      session = Session(
        name: cookieName,
        options: resolvedStore is CookieStore
            ? resolvedStore.defaultOptions
            : SessionOptions(
                secure: true,
                httpOnly: true,
                sameSite: SameSite.lax,
              ),
      );
    }

    ctx.set(sessionKey.name, session);
    final result = await next();
    try {
      await resolvedStore.write(req, res, session);
    } on Object catch (_) {}
    return result;
  };
}

/// Registers [SessionConfig] and its [SessionStore] with a Routed container.
class RoutedSessionsProvider extends ServiceProvider
    with ProvidesTypedConfiguration<SessionConfig> {
  /// Creates a provider, defaulting to an in-memory store with protected
  /// cookies.
  RoutedSessionsProvider([SessionConfig? configuration])
    : configuration =
          configuration ??
          SessionConfig(
            store: MemorySessionStore(
              codecs: [SecureCookie(useEncryption: true, useSigning: true)],
              defaultOptions: SessionOptions(
                secure: true,
                httpOnly: true,
                sameSite: SameSite.lax,
              ),
            ),
            defaultOptions: SessionOptions(
              secure: true,
              httpOnly: true,
              sameSite: SameSite.lax,
            ),
          );

  /// The configuration registered by this provider.
  @override
  final SessionConfig configuration;

  /// Registers the configured session objects in [container].
  @override
  void register(Container container) {
    final store = configuration.store;
    container
      ..instance<SessionConfig>(configuration)
      ..singleton<SessionStore>((_) async => store);
  }

  /// Completes provider startup; session registration requires no boot work.
  @override
  Future<void> boot(Container container) async {}
}

/// Registers the session provider factory in the shared provider registry.
void registerRoutedSessionsProviders() {
  ProviderRegistry.instance.register(
    'routed.sessions',
    factory: RoutedSessionsProvider.new,
    description: 'Session store and EngineContext session helpers.',
  );
}
