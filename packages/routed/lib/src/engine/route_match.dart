import 'package:routed_core/routed_core.dart' as core;

import 'engine.dart' show EngineRoute;

/// Routed compatibility wrapper over the generic core [core.RouteMatch].
class RouteMatch extends core.RouteMatch<EngineRoute> {
  RouteMatch({
    required super.matched,
    required super.isMethodMismatch,
    super.route,
  });
}
