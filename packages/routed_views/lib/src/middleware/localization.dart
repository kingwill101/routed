library;

import 'package:routed_core/routed_core.dart';
import 'package:routed_views/src/translation/locale_manager.dart';
import 'package:routed_views/src/translation/locale_resolution.dart';
import 'package:routed_views/src/translation/constants.dart';

/// Stub localization middleware — re-exported for backward compat.
Middleware localizationMiddleware(LocaleManager manager) {
  return (EngineContext ctx, Next next) async {
    final context = LocaleResolutionContext.fromContext(ctx);
    final locale = manager.resolve(context);
    ctx.set(kRequestLocaleAttribute, locale);
    return await next();
  };
}
