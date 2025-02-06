import 'package:routed/routed.dart';

import 'cookie_store.dart';
import 'options.dart';
import 'secure_cookie.dart';
import 'store.dart';

/// Creates session middleware with the specified options
Handler sessionMiddleware({
  Store? store,
  String name = 'session',
  Options? defaultOptions,
  List<SecureCookie>? codecs,
  bool useEncryption = false,
  bool useSigning = false,
}) {
  final options = defaultOptions ?? Options();
  final sessionStore = store ??
      CookieStore(
        defaultOptions: options,
        codecs: codecs ??
            [
              SecureCookie(
                key: SecureCookie.generateKey(),
                useEncryption: useEncryption,
                useSigning: useSigning,
              )
            ],
      );

  return (EngineContext ctx) async {
    final session = await sessionStore.read(ctx.request, name);
    ctx.set('session', session);

    await ctx.next();

    if (!ctx.response.isClosed) {
      await sessionStore.write(
        ctx.request,
        ctx.response,
        ctx.get('session'),
      );
    }
  };
}
