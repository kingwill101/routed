import 'package:routed/src/context/context.dart';
import 'package:routed_core/routed_core.dart' as core;

typedef ErrorObserver = core.ErrorObserver<EngineContext>;

class ErrorObserverRegistry extends core.ErrorObserverRegistry<EngineContext> {}
