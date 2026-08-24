import 'package:routed_core/routed_core.dart';

import 'node_runtime_js.dart';

/// Performs the defineVercelNodeHandlerRuntime operation.
void defineVercelNodeHandlerRuntime(Engine engine) {
  defineVercelNodeHandlers(engine);
}

/// Performs the defineVercelNodeHandlerFactoryRuntime operation.
void defineVercelNodeHandlerFactoryRuntime(Future<Engine> Function() factory) {
  defineVercelNodeHandlersAsync(factory);
}
