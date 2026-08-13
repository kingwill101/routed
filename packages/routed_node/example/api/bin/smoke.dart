import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node_api_sample/app.dart';

/// VM-friendly smoke for the sample API.
///
/// Runs the same [createSampleEngine] routes through [Engine.handlePortable]
/// (no Node sockets). Use this to verify handlers before a Node build.
Future<void> main() async {
  final engine = createSampleEngine();
  await engine.initialize();

  Future<void> hit(
    String method,
    String path, {
    String? body,
    Map<String, List<String>>? headers,
  }) async {
    final reqHeaders = PortableHeaders({
      'host': ['127.0.0.1'],
      'accept': ['application/json'],
      ...?headers,
    });
    if (body != null) {
      reqHeaders.set('content-type', 'application/json');
      reqHeaders.set('content-length', '${utf8.encode(body).length}');
    }

    final out = await engine.handlePortable(
      PortableRequest(
        method: method,
        uri: Uri.parse('http://127.0.0.1$path'),
        headers: reqHeaders,
        body: body == null
            ? const Stream.empty()
            : Stream.value(utf8.encode(body)),
        remoteAddress: '127.0.0.1',
      ),
    );

    // ignore: avoid_print
    print('$method $path → ${out.statusCode} ${out.bodyText}');
  }

  await hit('GET', '/');
  await hit('GET', '/health');
  await hit('GET', '/capabilities');
  await hit('GET', '/stream');
  await hit('GET', '/api/items');
  await hit('GET', '/api/items/1');
  await hit('GET', '/api/items/missing');
  await hit(
    'POST',
    '/api/items',
    body: jsonEncode({'name': 'gamma', 'qty': 7}),
  );
  await hit(
    'POST',
    '/echo',
    body: jsonEncode({'ok': true}),
    headers: {
      'x-trace': ['vm-smoke'],
    },
  );
  await hit('GET', '/api/items');
  await hit('DELETE', '/api/items/2');
  await hit('GET', '/api/items');

  // ignore: avoid_print
  print('smoke ok');
  await engine.close();
}
