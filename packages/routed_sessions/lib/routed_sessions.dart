library;
<<<<<<< HEAD
import 'dart:io';
=======
>>>>>>> a5d0ac8f (style: dart format across routed ecosystem)

import 'package:routed/routed.dart';
import 'package:server_sessions/server_sessions.dart';

const sessionKey = ContextKey<Session>('routed.session');

/// Default cookie name used when [sessionMiddleware] is called without [name].
const defaultSessionName = 'routed_session';

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
}

/// Adapts Routed's [Request] to the portable [SessionRequest] contract.
class _RoutedSessionRequest implements SessionRequest {
  _RoutedSessionRequest(this.request);

  final Request request;

  @override
  List<Cookie> get cookies => request.cookies;

  @override
  String header(String name) => request.header(name);
}

/// Adapts Routed's [Response] to the portable [SessionResponse] contract.
class _RoutedSessionResponse implements SessionResponse {
  _RoutedSessionResponse(this.response);

  final Response response;

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
    response.setCookie(
      name,
      value,
      maxAge: maxAge,
      path: path,
      domain: domain,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
    );
  }
}

/// Installs session handling for the given [store].
///
/// For every request the middleware:
/// 1. Reads (or creates) the session via `store.read(ctx.request, name)` and
///    places it under [sessionKey] so `ctx.session` / `ctx.hasSession` work.
/// 2. Runs the rest of the handler chain.
/// 3. Persists the session via `store.write(...)` (including destroys and
///    regenerations performed by the handler).
Middleware sessionMiddleware(
  SessionStore store, {
  String name = defaultSessionName,
}) {
  return (ctx, next) async {
    final request = _RoutedSessionRequest(ctx.request);
    final response = _RoutedSessionResponse(ctx.response);

    final session = await store.read(request, name);
    ctx.set(sessionKey.name, session);

    final res = await next();

    if (!ctx.isClosed) {
      final current = ctx.get<Session>(sessionKey.name) ?? session;
      await store.write(request, response, current);
    }
    return res;
  };
}

class RoutedSessionsProvider extends ServiceProvider {
  RoutedSessionsProvider(this.store);
  final SessionStore store;
  @override
  void register(Container container) {
    container.singleton<SessionStore>((_) async => store);
  }

  @override
  Future<void> boot(Container container) async {}
}
