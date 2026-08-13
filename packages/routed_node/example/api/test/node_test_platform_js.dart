import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_node/node.dart';
import 'package:routed_node_api_sample/app.dart';

Future<void> runNodeExampleIntegration() async {
  final engine = createSampleEngine();
  final handle = await serveNode(
    engine,
    host: '127.0.0.1',
    port: 0,
    echo: false,
  );
  try {
    final fetch = globalContext.getProperty('fetch'.toJS);
    final responsePromise = (fetch as JSFunction).callAsFunction(
      null,
      'http://127.0.0.1:${handle.port}/capabilities'.toJS,
    );
    final response = await (responsePromise as JSPromise<JSAny?>).toDart;
    final status =
        ((response as JSObject).getProperty('status'.toJS) as JSNumber)
            .toDartInt;
    if (status != 200) throw StateError('Expected 200, got $status');
  } finally {
    await handle.close(force: true);
    await engine.close();
  }
}
