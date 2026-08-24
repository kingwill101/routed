import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/routed_core.dart' show EngineContext;

import 'package:routed_logging/src/logging/context.dart';

/// Adds request-scoped logging accessors to [EngineContext].
extension EngineContextLogging on EngineContext {
  /// The logger associated with this request.
  contextual.Logger get logger => LoggingContext.currentLogger(this);

  /// The structured values associated with this request.
  Map<String, Object?> get loggerContext => LoggingContext.currentValues(this);
}
