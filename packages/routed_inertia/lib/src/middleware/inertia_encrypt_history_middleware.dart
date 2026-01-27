import 'package:routed/routed.dart';

import '../engine_context_inertia.dart';

/// Routed middleware that enables Inertia history encryption.
class InertiaEncryptHistoryMiddleware {
  Future<Response> call(EngineContext ctx, Next next) async {
    ctx.inertiaEncryptHistory();
    return next();
  }
}
