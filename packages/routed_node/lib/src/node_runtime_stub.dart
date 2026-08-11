import 'dart:async';

import 'package:routed_core/routed_core.dart';

/// VM / non-JS stub: real Node bind requires compiling this package for a
/// JavaScript runtime (`dart compile js` / dart2wasm with Node host).
Future<ServerHandle> bindNodeHttp(
  Engine engine,
  ServerOptions options, {
  bool echo = false,
}) {
  return Future.error(
    UnsupportedError(
      'NodeServerTransport requires a JavaScript/Node runtime. '
      'Compile with dart2js (or similar) targeting Node, or use '
      'package:routed_io on the Dart VM. '
      'Adapters (NodeRequestAdapter / NodeResponseAdapter) and '
      'Engine.handleConnection work on any platform with test doubles.',
    ),
  );
}
