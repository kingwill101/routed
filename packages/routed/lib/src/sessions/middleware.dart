import 'package:collection/collection.dart';
import 'package:routed/session.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';

/// Creates session middleware with the specified options
Middleware sessionMiddleware({
  Store? store,
  String name = 'session',
  Options? defaultOptions,
  List<SecureCookie>? codecs,
  bool useEncryption = false,
  bool useSigning = false,
}) {
  final options = defaultOptions ?? Options();
  final sessionStore =
      store ??
      CookieStore(
        defaultOptions: options,
        codecs:
            codecs ??
            [
              SecureCookie(
                key: SecureCookie.generateKey(),
                useEncryption: useEncryption,
                useSigning: useSigning,
              ),
            ],
      );

  return (EngineContext ctx, Next next) async {
    final session = await sessionStore.read(ctx.request, name);
    ctx.set('session', session);

    final initialSnapshot = _sessionSnapshot(session);
    final equality = const DeepCollectionEquality();

    var wrotePreCommit = false;
    if (!ctx.response.isClosed && session.isNew) {
      await sessionStore.write(ctx.request, ctx.response, session);
      wrotePreCommit = true;
    }

    final res = await next();

    if (!ctx.response.isClosed) {
      final currentSession = ctx.get<Session>('session') ?? session;
      final currentSnapshot = _sessionSnapshot(currentSession);
      final payloadChanged =
          !equality.equals(initialSnapshot, currentSnapshot) ||
          !identical(currentSession, session);

      final requiresWrite =
          currentSession.isDestroyed ||
          payloadChanged ||
          (!wrotePreCommit && currentSession.isNew);

      if (!requiresWrite) {
        return res;
      }

      final wroteSamePayload =
          wrotePreCommit && !currentSession.isDestroyed && !payloadChanged;
      if (wroteSamePayload) {
        return res;
      }

      await sessionStore.write(ctx.request, ctx.response, currentSession);
    }
    return res;
  };
}

Map<String, dynamic> _sessionSnapshot(Session session) {
  final snapshot = Map<String, dynamic>.from(session.toMap());
  snapshot.remove('last_accessed');
  return snapshot;
}
