import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/routed.dart' show EngineContext;

import 'context.dart';

extension EngineContextLogging on EngineContext {
  contextual.Logger get logger => LoggingContext.currentLogger(this);

  Map<String, Object?> get loggerContext => LoggingContext.currentValues(this);
}
