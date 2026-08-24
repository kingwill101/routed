import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/translation/constants.dart';
import 'package:routed_views/src/translation/locale_manager.dart';
import 'package:routed_views/src/translation/locale_resolution.dart';

/// Resolves and stores the request locale before downstream middleware runs.
///
/// The [manager] evaluates its configured resolver chain for every request.
/// The selected locale is stored under [kRequestLocaleAttribute], allowing
/// downstream handlers and view helpers to read it with
/// `ctx.get<String>(kRequestLocaleAttribute)`. The middleware does not write a
/// cookie or session value and returns the result of `next` unchanged.
///
/// Install it after request services have been created and before handlers that
/// need localization. `LocaleResolutionContext.fromContext` tolerates a
/// missing session service, so session-based resolution simply yields no value
/// when sessions are not configured.
Middleware localizationMiddleware(LocaleManager manager) {
  return (EngineContext ctx, Next next) async {
    final context = LocaleResolutionContext.fromContext(ctx);
    final locale = manager.resolve(context);
    ctx.set(kRequestLocaleAttribute, locale);
    return await next();
  };
}
