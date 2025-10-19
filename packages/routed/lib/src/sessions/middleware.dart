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

    // Pre-commit the session so the cookie is present even if the handler closes
    // the response (e.g. via ctx.string/json). We'll update again after next()
    // if the response is still open to capture any later changes.
    if (!ctx.response.isClosed) {
      await sessionStore.write(ctx.request, ctx.response, session);
    }

    final res = await next();

    if (!ctx.response.isClosed) {
      final sess = ctx.get<Session>('session') ?? session;
      await sessionStore.write(ctx.request, ctx.response, sess);
    }
    return res;
  };
}
