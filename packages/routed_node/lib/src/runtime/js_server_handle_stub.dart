import 'package:routed_core/routed_core.dart';

import 'runtime.dart';

Never unsupportedListener(String runtime) {
  throw UnsupportedError('$runtime listener requires a JavaScript host.');
}

Future<ServerHandle> unsupportedServe(
  String runtime,
  Engine engine,
  RoutedNodeRuntimeInfo info,
) async {
  unsupportedListener(runtime);
}
