import 'package:routed_core/routed_core.dart';

import 'runtime.dart';

/// Performs the unsupportedListener operation.
Never unsupportedListener(String runtime) {
  throw UnsupportedError('$runtime listener requires a JavaScript host.');
}

/// Performs the unsupportedServe operation.
Future<ServerHandle> unsupportedServe(
  String runtime,
  Engine engine,
  RoutedNodeRuntimeInfo info,
) async {
  unsupportedListener(runtime);
}
