import 'package:routed_core/routed_core.dart';

import 'node_runtime_js.dart';

void defineVercelNodeHandlerRuntime(Engine engine) {
  defineVercelNodeHandlers(engine);
}

void defineVercelNodeHandlerFactoryRuntime(Future<Engine> Function() factory) {
  defineVercelNodeHandlersAsync(factory);
}
