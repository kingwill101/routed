import 'dart:async';
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
    unawaited(request.close());

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
    final engine = Engine(providers: Engine.defaultProviders)
      ..get('/ping', (ctx) => ctx.string('pong'))
      ..get('/native', (ctx) {
        final request = ctx.request;
        // This deliberately checks native identity so request-size wrapping
        // cannot make the request look like a portable request.
        return ctx.string('${request.hasNativeHttpRequest}:${request.method}');
      });
    await engine.initialize();
    addTearDown(engine.close);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((req) {
      final conn = IoHttpConnection(req);
      unawaited(engine.handleConnection(conn.connection));
    });

    final client = HttpClient();
    addTearDown(client.close);
    final response = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/ping'))
        .then((r) => r.close());
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200);
    expect(body, 'pong');

    final nativeResponse = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/native'))
        .then((r) => r.close());
    final nativeBody = await nativeResponse.transform(utf8.decoder).join();
    expect(nativeResponse.statusCode, 200);
    expect(nativeBody, 'true:GET');
  });

  test('portableRequestFromIo maps method, uri, headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final seen = server.first;
    final client = HttpClient();
    addTearDown(client.close);
    unawaited(() async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/z?q=1'),
      );
      request.headers.set('x-io', 'yes');
      await request.close();
    }());

    final httpRequest = await seen;
    final portable = portableRequestFromIo(httpRequest);
    expect(portable.method, 'GET');
    expect(portable.uri.path, '/z');
    expect(portable.uri.queryParameters['q'], '1');
    expect(portable.headers.get('x-io'), 'yes');
    expect(portable.remoteAddress, isNotNull);

    final fromConn = IoHttpConnection(httpRequest).toPortableRequest();
    expect(fromConn.uri.path, '/z');

    httpRequest.response.statusCode = 204;
    await httpRequest.response.close();
  });

  test('dispatchIoExchange serves via handlePortable', () async {
    final engine = Engine(providers: Engine.defaultProviders)
      ..get('/ping', (ctx) => ctx.string('pong'));
    await engine.initialize();
    addTearDown(engine.close);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((req) {
      unawaited(dispatchIoExchange(engine, req));
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

  test('IoServerTransport portableEdge serves routes', () async {
    final engine = Engine(providers: Engine.defaultProviders)
      ..get('/ok', (ctx) => ctx.string('edge'));
    await engine.initialize();
    addTearDown(engine.close);

    final handle = await const IoServerTransport(
      portableEdge: true,
    ).serve(engine, const ServerOptions(port: 0));
    addTearDown(() => handle.close(force: true));

    final client = HttpClient();
    addTearDown(client.close);
    final response = await client
        .getUrl(Uri.parse('http://127.0.0.1:${handle.port}/ok'))
        .then((r) => r.close());
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200);
    expect(body, 'edge');
  });
}
