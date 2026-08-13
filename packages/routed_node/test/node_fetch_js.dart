import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_node/node.dart';
// The package import is supplied by the workspace example during JS runs.
// ignore: depend_on_referenced_packages
import 'package:routed_node_api_sample/app.dart';

Future<void> runNodeFetchIntegration() async {
  final engine = createSampleEngine();
  final handle = await serveNode(
    engine,
    host: '127.0.0.1',
    port: 0,
    echo: false,
  );
  try {
    final fetch = globalContext.getProperty('fetch'.toJS);
    if (fetch == null || !fetch.isA<JSFunction>()) {
      throw StateError('Node global fetch is unavailable');
    }

    final url = 'http://127.0.0.1:${handle.port}/health';
    final responsePromise = (fetch as JSFunction).callAsFunction(
      null,
      url.toJS,
    );
    final response = await (responsePromise as JSPromise<JSAny?>).toDart;
    final responseObject = response as JSObject;
    final status =
        (responseObject.getProperty('status'.toJS) as JSNumber).toDartInt;
    final textMethod = responseObject.getProperty('text'.toJS) as JSFunction;
    final bodyPromise = textMethod.callAsFunction(responseObject);
    final body = await (bodyPromise as JSPromise<JSAny?>).toDart;

    if (status != 200) throw StateError('Expected 200, got $status');
    final decoded = jsonDecode((body as JSString).toDart) as Map;
    if (decoded['ok'] != true) throw StateError('Unexpected response: $body');
  } finally {
    await handle.close(force: true);
    await engine.close();
  }
}
