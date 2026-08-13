import 'dart:async';

import 'package:routed_node/routed_node.dart';
import 'package:routed_node_api_sample/app.dart';

/// Node.js host entrypoint for the sample API.
///
/// On a JavaScript/Node runtime (after `dart compile js`), this binds with
/// `http.createServer` via [serveNode].
///
/// On the Dart VM this throws [UnsupportedError] — use `bin/smoke.dart` to
/// exercise the same routes without Node, or compile for Node first
/// (see README).
///
/// Compile-time config (dart2js / `dart run` with `-D`):
/// ```
/// dart compile js bin/server.dart -o build/server.js \
///   -DHOST=0.0.0.0 -DPORT=8080
/// ```
Future<void> main(List<String> args) async {
  final host = _resolveHost(args);
  final port = _resolvePort(args);

  final engine = createSampleEngine();

  // ignore: avoid_print
  print('Starting routed_node sample API on http://$host:$port …');

  late final dynamic handle;
  try {
    handle = await serveNode(engine, host: host, port: port, echo: true);
  } catch (error, stackTrace) {
    // ignore: avoid_print
    print('Failed to start routed_node: $error');
    // ignore: avoid_print
    print(stackTrace);
    rethrow;
  }

  // ignore: avoid_print
  print('Listening on http://${handle.host}:${handle.port}');
  // ignore: avoid_print
  print('Try: curl http://127.0.0.1:${handle.port}/health');

  // The listener's native server keeps Node's event loop alive.
  await Completer<void>().future;
}

String _resolveHost(List<String> args) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--host') return args[i + 1];
  }
  return const String.fromEnvironment('HOST', defaultValue: '0.0.0.0');
}

int _resolvePort(List<String> args) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') {
      return int.tryParse(args[i + 1]) ?? 8080;
    }
  }
  return const int.fromEnvironment('PORT', defaultValue: 8080);
}
