import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_node/bun.dart';
import 'package:routed_node_api_sample/app.dart';

Future<void> runBunExampleIntegration() async {
  final engine = createSampleEngine();
  final handle = await serveBun(engine, host: '127.0.0.1', port: 0);
  try {
    final fetch = globalContext.getProperty('fetch'.toJS);
    final result = (fetch as JSFunction).callAsFunction(
      null,
      'http://127.0.0.1:${handle.port}/health'.toJS,
    );
    final response = await (result as JSPromise<JSAny?>).toDart;
    final status =
        ((response as JSObject).getProperty('status'.toJS) as JSNumber)
            .toDartInt;
    if (status != 200) throw StateError('Expected 200, got $status');
  } finally {
    await handle.close(force: true);
    await engine.close();
  }
}
