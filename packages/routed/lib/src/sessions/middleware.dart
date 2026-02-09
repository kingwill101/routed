import 'package:collection/collection.dart';
import 'package:routed/session.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/router/types.dart';

/// Creates session middleware with the specified options.
///
/// When [store] and [name] are not explicitly provided, the middleware will
/// attempt to resolve a [SessionConfig] from the request container at runtime
/// (registered via [withSessionConfig] or [SessionServiceProvider]). Explicit
/// arguments always take precedence over the container-resolved config.
///
/// If no [SessionConfig] is available from the container and no explicit
/// [store] is given, a default [CookieStore] with a random key is created as
/// a fallback.
Middleware sessionMiddleware({
  Store? store,
  String? name,
  Options? defaultOptions,
  List<SecureCookie>? codecs,
  bool useEncryption = false,
  bool useSigning = false,
}) {
  // Build a fallback store eagerly (once) so crypto keys remain stable across
  // requests when neither an explicit store nor a container config is present.
  final fallbackStore = store == null
      ? CookieStore(
          defaultOptions: defaultOptions ?? Options(),
          codecs:
              codecs ??
              [
                SecureCookie(
                  key: SecureCookie.generateKey(),
                  useEncryption: useEncryption,
                  useSigning: useSigning,
                ),
              ],
        )
      : null;

  return (EngineContext ctx, Next next) async {
    final Store resolvedStore;
    final String resolvedName;

    if (store != null) {
      // Explicit store override — use it directly.
      resolvedStore = store;
      resolvedName = name ?? 'session';
    } else {
      // Try resolving SessionConfig from the request/engine container.
      final config = _resolveSessionConfig(ctx);
      if (config != null) {
        resolvedStore = config.store;
        resolvedName = name ?? config.cookieName;
      } else {
        // No container config available — use the pre-built fallback.
        resolvedStore = fallbackStore!;
        resolvedName = name ?? 'session';
      }
    }

    final session = await resolvedStore.read(ctx.request, resolvedName);
    ctx.set('session', session);

    final initialSnapshot = _sessionSnapshot(session);
    final equality = const DeepCollectionEquality();

    var wrotePreCommit = false;
    if (!ctx.response.isClosed && session.isNew) {
      await resolvedStore.write(ctx.request, ctx.response, session);
      wrotePreCommit = true;
    }

    final res = await next();

    if (!ctx.isClosed) {
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

      await resolvedStore.write(ctx.request, ctx.response, currentSession);
    }
    return res;
  };
}

/// Attempts to resolve [SessionConfig] from the engine or request container.
///
/// Returns `null` if no container is available or if [SessionConfig] has not
/// been registered.
SessionConfig? _resolveSessionConfig(EngineContext ctx) {
  try {
    final container = ctx.container;
    if (container.has<SessionConfig>()) {
      return container.get<SessionConfig>();
    }
  } catch (_) {
    // No container associated with this context — fall through.
  }
  return null;
}

Map<String, dynamic> _sessionSnapshot(Session session) {
  final snapshot = Map<String, dynamic>.from(session.toMap());
  snapshot.remove('last_accessed');
  return snapshot;
}
