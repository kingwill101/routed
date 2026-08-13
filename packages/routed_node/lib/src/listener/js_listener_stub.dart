import 'package:routed_core/routed_core.dart';

import '../runtime/runtime.dart';

Never unsupportedListener(String runtime) {
  throw UnsupportedError('$runtime listener requires a JavaScript host.');
}

Future<ServerHandle> serveJsListener(
  String runtime,
  Engine engine, {
  required String host,
  required int port,
  required RoutedNodeRuntimeInfo info,
}) async {
  unsupportedListener(runtime);
}
