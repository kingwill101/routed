library;

import 'dart:io';

import 'src/config.dart';

export 'src/config.dart';

import 'package:routed_core/routed_core.dart';
import 'package:server_sessions/server_sessions.dart';

export 'package:server_sessions/server_sessions.dart';

const sessionKey = ContextKey<Session>('routed.session');

extension SessionEngineContext on EngineContext {
  Session get session {
    final s = get<Session>(sessionKey.name);
    if (s == null) throw StateError('Session middleware not configured');
    return s;
  }

  bool get hasSession => get<Session>(sessionKey.name) != null;

  T? getSession<T>(String key) {
    try {
      return session.getValue<T>(key);
    } catch (_) {
      return null;
    }
  }

  void setSession(String key, dynamic value) {
    try {
      session.setValue(key, value);
    } catch (_) {}
  }

  void removeSession(String key) => session.values.remove(key);
  void clearSession() => session.values.clear();
  bool hasSessionKey(String key) => session.values.containsKey(key);
  Map<String, dynamic> get sessionData => Map.from(session.values);
  String get sessionId => session.id;
  void destroySession() => session.destroy();

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
    } catch (_) {}
  }

  bool hasFlashMessages() {
    try {
      final flashes = session.values['_flash'] as List?;
      return flashes != null && flashes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<dynamic> getFlashMessages({
    bool withCategories = false,
    List<String>? categoryFilter,
  }) {
    try {
      final flashes = session.values['_flash'];
      if (flashes is! List || flashes.isEmpty) return [];
      var source = flashes
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
      return filtered.map((m) => m['message'] as String).toList();
    } catch (_) {
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
    } catch (_) {
      return const [];
    }
  }

  @override
  String header(String name) {
    try {
      final v = (ctx.request.headers as dynamic).value(name);
      if (v is String && v.isNotEmpty) return v;
      if (v is List && v.isNotEmpty) return v.first.toString();
    } catch (_) {}
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
    } catch (_) {}
    try {
      final headers = ctx.request.headers;
      final v = headers.value(name);
      if (v != null) return v;
    } catch (_) {}
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
    } catch (_) {
      try {
        final sb = StringBuffer('$name=$value; Path=$path');
        if (maxAge != null) sb.write('; Max-Age=$maxAge');
        ctx.response.headers.set(HttpHeaders.setCookieHeader, sb.toString());
      } catch (_) {}
    }
  }
}

Middleware sessionMiddleware([SessionStore? store]) {
  return (EngineContext ctx, Next next) async {
    SessionConfig? config;
    SessionStore? effectiveStore = store;
    String cookieName = 'routed_session';

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
      // No explicit store — fall back to cookie store derived from config or default
      final SessionOptions opts = SessionOptions(
        path: '/',
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
    } catch (_) {
      session = Session(
        name: cookieName,
        options: resolvedStore is CookieStore
            ? resolvedStore.defaultOptions
            : SessionOptions(),
      );
    }

    ctx.set(sessionKey.name, session);
    final result = await next();
    try {
      await resolvedStore.write(req, res, session);
    } catch (_) {}
    return result;
  };
}

class RoutedSessionsProvider extends ServiceProvider
    with ProvidesTypedConfiguration<SessionConfig> {
  /// Defaults to an in-memory session store with signed cookies.
  RoutedSessionsProvider([SessionConfig? configuration])
    : configuration =
          configuration ??
          SessionConfig(
            store: MemorySessionStore(
              codecs: [SecureCookie(useEncryption: true, useSigning: true)],
              defaultOptions: SessionOptions(path: '/', httpOnly: true),
            ),
            defaultOptions: SessionOptions(path: '/', httpOnly: true),
          );

  @override
  final SessionConfig configuration;

  @override
  void register(Container container) {
    final store = configuration.store;
    container.instance<SessionConfig>(configuration);
    container.singleton<SessionStore>((_) async => store);
  }

  @override
  Future<void> boot(Container container) async {}
}

/// Registers the session provider factory in the shared registry.
void registerRoutedSessionsProviders() {
  ProviderRegistry.instance.register(
    'routed.sessions',
    factory: RoutedSessionsProvider.new,
    description: 'Session store and EngineContext session helpers.',
  );
}
