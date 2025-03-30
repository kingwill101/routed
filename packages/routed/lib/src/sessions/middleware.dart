import 'package:routed/routed.dart';
import 'package:routed/session.dart';


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
      final sessionData = ctx.get<dynamic>('session');
      if (sessionData is Session) {
        await sessionStore.write(
          ctx.request,
          ctx.response,
          sessionData,
        );
      }
    }
  };
}
