import 'dart:convert';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

/// Minimal in-memory adapters used to exercise the portable
/// [Engine.handleConnection] bridge without `dart:io` sockets.
final class _MemoryRequestAdapter implements RequestAdapter {
  _MemoryRequestAdapter({
    required this.method,
    required this.uri,
    Map<String, List<String>>? headers,
    List<int>? body,
    this.remoteAddress,
  }) : headers = headers ?? const {},
       _body = body ?? const [];

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final Map<String, List<String>> headers;

  final List<int> _body;

  @override
  Stream<List<int>> get body =>
      _body.isEmpty ? const Stream.empty() : Stream.value(_body);

  @override
  final String? remoteAddress;
}

final class _MemoryResponseAdapter implements ResponseAdapter {
  int _statusCode = 200;
  final Map<String, List<String>> headers = {};
  final BytesBuilder body = BytesBuilder();
  bool closed = false;

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) => _statusCode = value;

  @override
  void setHeader(String name, String value) {
    headers[name.toLowerCase()] = [value];
  }

  @override
  void addHeader(String name, String value) {
    headers.putIfAbsent(name.toLowerCase(), () => []).add(value);
  }

  @override
  void write(List<int> bytes) {
    body.add(bytes);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test('handleConnection serves routes via portable adapters', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.get('/ping', (ctx) => ctx.string('pong'));
    await engine.initialize();
    addTearDown(engine.close);

    final response = _MemoryResponseAdapter();
    final connection = HttpConnection(
      _MemoryRequestAdapter(
        method: 'GET',
        uri: Uri.parse('http://example.test/ping'),
        headers: {
          'host': ['example.test'],
          'accept': ['text/plain'],
        },
        remoteAddress: '127.0.0.1',
      ),
      response,
    );

    await engine.handleConnection(connection);

    expect(response.closed, isTrue);
    expect(response.statusCode, 200);
    expect(utf8.decode(response.body.takeBytes()), 'pong');
  });

  test('handleConnection returns 404 for unknown routes', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    await engine.initialize();
    addTearDown(engine.close);

    final response = _MemoryResponseAdapter();
    await engine.handleConnection(
      HttpConnection(
        _MemoryRequestAdapter(
          method: 'GET',
          uri: Uri.parse('http://example.test/missing'),
        ),
        response,
      ),
    );

    expect(response.closed, isTrue);
    expect(response.statusCode, 404);
  });

  test('handleConnection reads portable request body', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.post('/echo', (ctx) async {
      final body = await ctx.request.body();
      return ctx.string(body);
    });
    await engine.initialize();
    addTearDown(engine.close);

    final response = _MemoryResponseAdapter();
    final payload = utf8.encode('hello-node');
    await engine.handleConnection(
      HttpConnection(
        _MemoryRequestAdapter(
          method: 'POST',
          uri: Uri.parse('http://example.test/echo'),
          headers: {
            'content-type': ['text/plain'],
            'content-length': ['${payload.length}'],
          },
          body: payload,
        ),
        response,
      ),
    );

    expect(response.statusCode, 200);
    expect(utf8.decode(response.body.takeBytes()), 'hello-node');
  });

  test('handlePortable returns value-style PortableResponse', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.get('/hi', (ctx) => ctx.string('hello'));
    await engine.initialize();
    addTearDown(engine.close);

    final out = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('http://example.test/hi'),
        headers: PortableHeaders({
          'host': ['example.test'],
        }),
      ),
    );

    expect(out.statusCode, 200);
    expect(out.bodyText, 'hello');
  });

  test('PortableRequest.fromAdapter round-trips fields', () {
    final adapter = _MemoryRequestAdapter(
      method: 'PUT',
      uri: Uri.parse('http://example.test/a'),
      headers: {
        'x': ['1'],
      },
      remoteAddress: '1.2.3.4',
    );
    final portable = PortableRequest.fromAdapter(adapter);
    expect(portable.method, 'PUT');
    expect(portable.uri.path, '/a');
    expect(portable.headers.get('x'), '1');
    expect(portable.remoteAddress, '1.2.3.4');

    final again = PortableRequest.fromAdapter(portable.asAdapter());
    expect(again.method, 'PUT');
    expect(again.uri.path, '/a');
  });

  test('writePortableResponse fills a ResponseAdapter', () async {
    final sink = RecordingResponseAdapter();
    await writePortableResponse(
      PortableResponse(
        statusCode: 201,
        headers: PortableHeaders({
          'content-type': ['text/plain'],
        }),
        bodyBytes: utf8.encode('created'),
      ),
      sink,
    );
    final out = sink.toPortableResponse();
    expect(out.statusCode, 201);
    expect(out.headers.get('content-type'), 'text/plain');
    expect(out.bodyText, 'created');
  });

  test('Request.fromAdapter is portable dual-mode', () async {
    final adapter = _MemoryRequestAdapter(
      method: 'GET',
      uri: Uri.parse('http://api.test/items?x=1'),
      headers: {
        'host': ['api.test'],
        'cookie': ['a=1; b=2'],
        'content-length': ['5'],
      },
      body: utf8.encode('hello'),
      remoteAddress: '10.0.0.1',
    );
    final request = Request.fromAdapter(
      adapter,
      const {},
      EngineConfig(),
    );

    expect(request.isPortable, isTrue);
    expect(request.hasNativeHttpRequest, isFalse);
    expect(request.method, 'GET');
    expect(request.path, '/items');
    expect(request.queryParameters['x'], '1');
    expect(request.host, 'api.test');
    expect(request.remoteAddr, '10.0.0.1');
    expect(request.cookies.map((c) => c.name), containsAll(['a', 'b']));
    expect(await request.body(), 'hello');
    expect(() => request.httpRequest, throwsUnsupportedError);
  });

  test('Response.fromAdapter writes status body headers', () async {
    final sink = RecordingResponseAdapter();
    final response = Response.fromAdapter(sink);
    expect(response.isPortable, isTrue);
    expect(response.hasNativeHttpResponse, isFalse);

    response.statusCode = 201;
    response.setHeader('X-Test', 'yes');
    await response.string('created', statusCode: 201);

    expect(sink.statusCode, 201);
    expect(sink.isClosed, isTrue);
    final out = sink.toPortableResponse();
    expect(out.bodyText, 'created');
  });

  test('domain constraints work via AdapterConstraintView', () {
    final route = EngineRoute(
      method: 'GET',
      path: '/x',
      handler: (ctx) => ctx.string('ok'),
      patternRegistry: RoutePatternRegistry.defaults(),
      middlewares: const [],
      constraints: {'domain': r'^api\.example$'},
    );

    final ok = AdapterConstraintView(
      _MemoryRequestAdapter(
        method: 'GET',
        uri: Uri.parse('http://api.example/x'),
        headers: {
          'host': ['api.example'],
        },
      ),
    );
    expect(route.validateConstraints(ok), isTrue);

    final bad = AdapterConstraintView(
      _MemoryRequestAdapter(
        method: 'GET',
        uri: Uri.parse('http://other.example/x'),
        headers: {
          'host': ['other.example'],
        },
      ),
    );
    expect(route.validateConstraints(bad), isFalse);
  });
}
