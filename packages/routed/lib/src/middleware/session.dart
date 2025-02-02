import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/sessions/store.dart';

/// Creates a middleware function that manages session state for the current request.
///
/// The `sessionMiddleware` function takes a `Store` instance and an optional `sessionName`
/// parameter to configure the session management behavior. It returns a middleware function
/// that can be used in the application's middleware chain.
///
/// The middleware function performs the following steps:
/// 1. Retrieves the session for the current request from the `Store` instance.
/// 2. Stores the session in the `EngineContext` under the key 'session'.
/// 3. Calls the next middleware in the chain using `ctx.next()`.
/// 4. If the request was not aborted or closed, saves the session back to the `Store` instance.
Middleware sessionMiddleware(
  Store store, {
  String sessionName = 'routed_session',
}) {
  return (EngineContext ctx) async {
    final session =
        await store.getSession(ctx.request.httpRequest, sessionName);

    ctx.set('session', session);

    await ctx.next();

    if (!ctx.isAborted && !ctx.isClosed) {
      await store.saveSession(
        ctx.request.httpRequest,
        ctx.response.httpResponse,
        session,
      );
    }
  };
}
