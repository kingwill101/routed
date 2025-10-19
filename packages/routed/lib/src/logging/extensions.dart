import 'package:contextual/contextual.dart' as contextual;

import '../context/context.dart';
import 'context.dart';

extension EngineContextLogging on EngineContext {
  contextual.Logger get logger => LoggingContext.currentLogger();

  Map<String, Object?> get loggerContext => LoggingContext.currentValues();
}
