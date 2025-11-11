/// Middleware that resolves and stores the active locale for each request.
library;

import 'package:routed/routed.dart';
import 'package:routed/src/translation/constants.dart';
import 'package:routed/src/translation/locale_manager.dart';
import 'package:routed/src/translation/locale_resolution.dart';

/// Creates middleware that runs the [LocaleManager] before downstream handlers.
///
/// The resolved locale is stored under [kRequestLocaleAttribute] so helpers
/// such as [trans] can pick it up.
Middleware localizationMiddleware(LocaleManager manager) {
  return (EngineContext ctx, Next next) async {
    final context = LocaleResolutionContext.fromContext(ctx);
    final locale = manager.resolve(context);
    ctx.set(kRequestLocaleAttribute, locale);
    return await next();
  };
}
