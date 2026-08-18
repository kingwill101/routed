library;

import 'dart:io';

import 'src/config.dart';

export 'src/config.dart';

import 'package:routed_core/providers.dart' show ProviderRegistry;
import 'package:routed_core/routed_core.dart';
import 'package:server_sessions/server_sessions.dart';

export 'package:server_sessions/server_sessions.dart';
/// Registers session configuration in the engine container.
EngineOpt withSessionConfig(SessionConfig config) {
  return (Engine engine) {
    engine.appConfig.set('session.config', config);
    engine.container.instance<SessionConfig>(config);
  };
}

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

Middleware sessionMiddleware([dynamic store]) {
  return (EngineContext ctx, Next next) async {
    SessionConfig? config;
    dynamic effectiveStore = store;
    String cookieName = 'routed_session';

    try {
      final container = (ctx as dynamic).container as Container;
      if (container.has<SessionConfig>()) {
        config = container.get<SessionConfig>();
        cookieName = config.cookieName;
        effectiveStore ??= (config as dynamic).store;
      }
      if (effectiveStore == null && container.has<SessionStore>()) {
        effectiveStore = await container.make<SessionStore>();
      }
    } catch (_) {}

    // Ignore incompatible stores supplied through untyped configuration.
    if (effectiveStore != null && effectiveStore is! SessionStore) {
      effectiveStore = null;
    }

    if (effectiveStore == null) {
      // No explicit store — fall back to cookie store derived from config or default
      final SessionOptions opts = SessionOptions(
        path: '/',
        httpOnly: true,
        sameSite: SameSite.lax,
      );
      List<SecureCookie> codecs;
      try {
        if (config != null && (config.codecs as List).isNotEmpty) {
          final List<dynamic> raw = config.codecs as List;
          codecs = raw.map((e) {
            final dynamic d = e as dynamic;
            final dynamic k = d.key;
            if (k != null) {
              return SecureCookie(
                key: k,
                useEncryption: d.useEncryption == true,
                useSigning: d.useSigning == true,
              );
            }
            return SecureCookie(useEncryption: true, useSigning: true);
          }).toList();
          if (codecs.isEmpty) throw StateError('empty');
        } else {
          codecs = [SecureCookie(useEncryption: true, useSigning: true)];
        }
      } catch (_) {
        codecs = [SecureCookie(useEncryption: true, useSigning: true)];
      }
      effectiveStore = CookieStore(codecs: codecs, defaultOptions: opts);
      cookieName = config?.cookieName ?? cookieName;
    }

    final req = _EngineSessionRequest(ctx);
    final res = _EngineSessionResponse(ctx);

    // effectiveStore is now non-null after fallback
    final dynamic resolvedStore = effectiveStore!;
    Session session;
    try {
      session =
          await (resolvedStore as dynamic).read(req, cookieName) as Session;
    } catch (_) {
      session = Session(
        name: cookieName,
        options: resolvedStore is CookieStore
            ? (resolvedStore as dynamic).defaultOptions as SessionOptions
            : SessionOptions(),
      );
    }

    ctx.set(sessionKey.name, session);
    final result = await next();
    try {
      await (resolvedStore as dynamic).write(req, res, session);
    } catch (_) {}
    return result;
  };
}

class RoutedSessionsProvider extends ServiceProvider {
  /// Defaults to an in-memory session store with signed cookies.
  RoutedSessionsProvider([SessionStore? store])
    : store =
          store ??
          MemorySessionStore(
            codecs: [SecureCookie(useEncryption: true, useSigning: true)],
            defaultOptions: SessionOptions(path: '/', httpOnly: true),
          );

  final SessionStore store;

  @override
  void register(Container container) {
    container.singleton<SessionStore>((_) async => store);
  }

  @override
  Future<void> boot(Container container) async {}
}

/// Registers `routed.sessions` for `http.providers` resolution.
void registerRoutedSessionsProviders() {
  ProviderRegistry.instance.register(
    'routed.sessions',
    factory: RoutedSessionsProvider.new,
    description: 'Session store and EngineContext session helpers.',
  );
}
