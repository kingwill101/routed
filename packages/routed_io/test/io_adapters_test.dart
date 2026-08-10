import 'dart:convert';
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_io/routed_io.dart';
import 'package:test/test.dart';

void main() {
  test('IoHttpConnection exposes adapters and native request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final port = server.port;
    late IoHttpConnection conn;
    final seen = server.first.then((req) {
      conn = IoHttpConnection(req);
      return req;
    });

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/hello?x=1'),
    );
    request.headers.set('x-test', 'yes');
    // ignore: unawaited_futures
    request.close();

    await seen;

    expect(conn.requestAdapter.method, 'GET');
    expect(conn.requestAdapter.uri.path, '/hello');
    expect(conn.requestAdapter.uri.queryParameters['x'], '1');
    expect(conn.requestAdapter.headers['x-test']?.first, 'yes');
    expect(conn.requestAdapter, isA<NativeRequestHandle>());
    expect(conn.requestAdapter.nativeRequest, isA<HttpRequest>());
    expect(conn.connection.request, same(conn.requestAdapter));
    expect(conn.connection.response, same(conn.responseAdapter));

    conn.responseAdapter.statusCode = 204;
    await conn.responseAdapter.close();
  });

  test('Engine.handleConnection accepts IoHttpConnection', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.get('/ping', (ctx) => ctx.string('pong'));
    await engine.initialize();
    addTearDown(engine.close);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((req) {
      final conn = IoHttpConnection(req);
      // ignore: unawaited_futures
      engine.handleConnection(conn.connection);
    });

    final client = HttpClient();
    addTearDown(client.close);
    final response = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/ping'))
        .then((r) => r.close());
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200);
    expect(body, 'pong');
  });
}
