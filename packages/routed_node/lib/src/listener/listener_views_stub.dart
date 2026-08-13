import 'dart:js_interop';

import 'package:routed_core/routed_core.dart';

Future<JSObject> hostCreateServer(
  String runtime,
  Engine engine, {
  required String host,
  required int port,
}) async {
  throw UnsupportedError(
    '$runtime listener requires JavaScript host bindings.',
  );
}
