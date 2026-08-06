library;
import 'package:routed/routed.dart';
import 'package:server_sessions/server_sessions.dart';

const sessionKey = ContextKey<Session>('routed.session');

extension SessionEngineContext on EngineContext {
  Session get session => mustGet<Session>(sessionKey.name);
  bool get hasSession => get<Session>(sessionKey.name) != null;
}

Middleware sessionMiddleware(SessionStore store) {
  return (ctx, next) async {
    return next();
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
