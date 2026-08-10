import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node/routed_node.dart';
import 'package:test/test.dart';

final class _FakeIncoming implements NodeIncomingView {
  _FakeIncoming({
    required this.method,
    required this.url,
    Map<String, Object?>? rawHeaders,
    List<int>? body,
    this.remoteAddress,
  }) : rawHeaders = rawHeaders ?? const {},
       _body = body ?? const [];

  @override
  final String method;

  @override
  final String url;

  @override
  final Map<String, Object?> rawHeaders;

  final List<int> _body;

  @override
  Stream<List<int>> get body =>
      _body.isEmpty ? const Stream.empty() : Stream.value(_body);

  @override
  final String? remoteAddress;
}

final class _FakeOutgoing implements NodeServerResponseView {
  int? statusCode;
  Map<String, Object>? headers;
  final BytesBuilder body = BytesBuilder();
  bool _finished = false;

  @override
  void writeHead(int statusCode, Map<String, Object> headers) {
    this.statusCode = statusCode;
    this.headers = Map<String, Object>.from(headers);
  }

  @override
  void write(List<int> bytes) {
    body.add(bytes);
  }

  @override
  void end([List<int>? bytes]) {
    if (bytes != null) body.add(bytes);
    _finished = true;
  }

  @override
  bool get finished => _finished;
}

void main() {
  test('NodeRequestAdapter normalizes headers and URI', () {
    final adapter = NodeRequestAdapter(
      _FakeIncoming(
        method: 'GET',
        url: '/hello?x=1',
        rawHeaders: {
          'Host': 'api.example',
          'X-Test': ['a', 'b'],
          'accept': 'text/plain',
        },
        remoteAddress: '10.0.0.2',
      ),
      baseUri: Uri.parse('http://api.example'),
    );

    expect(adapter.method, 'GET');
    expect(adapter.uri.path, '/hello');
    expect(adapter.uri.queryParameters['x'], '1');
    expect(adapter.headers['host']?.first, 'api.example');
    expect(adapter.headers['x-test'], ['a', 'b']);
    expect(adapter.headers['accept']?.first, 'text/plain');
    expect(adapter.remoteAddress, '10.0.0.2');
    expect(adapter, isNot(isA<NativeRequestHandle>()));
  });

  test('NodeResponseAdapter writeHead + body + close', () async {
    final outgoing = _FakeOutgoing();
    final adapter = NodeResponseAdapter(outgoing);

    adapter.statusCode = 201;
    adapter.setHeader('Content-Type', 'text/plain');
    adapter.addHeader('X-Extra', '1');
    adapter.write(utf8.encode('created'));
    await adapter.close();

    expect(outgoing.statusCode, 201);
    expect(outgoing.headers?['Content-Type'], 'text/plain');
    expect(outgoing.headers?['X-Extra'], '1');
    expect(utf8.decode(outgoing.body.takeBytes()), 'created');
    expect(outgoing.finished, isTrue);
  });

  test('Engine.handleConnection serves via NodeHttpConnection', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.get('/ping', (ctx) => ctx.string('pong'));
    await engine.initialize();
    addTearDown(engine.close);

    final outgoing = _FakeOutgoing();
    final conn = NodeHttpConnection(
      _FakeIncoming(
        method: 'GET',
        url: '/ping',
        rawHeaders: {
          'host': ['localhost'],
        },
      ),
      outgoing,
      baseUri: Uri.parse('http://localhost'),
    );

    await engine.handleConnection(conn.connection);

    expect(outgoing.finished, isTrue);
    expect(outgoing.statusCode, 200);
    expect(utf8.decode(outgoing.body.takeBytes()), 'pong');
  });

  test('dispatchNodeExchange uses handlePortable value edge', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.get('/ping', (ctx) => ctx.string('pong'));
    await engine.initialize();
    addTearDown(engine.close);

    final outgoing = _FakeOutgoing();
    await dispatchNodeExchange(
      engine,
      _FakeIncoming(
        method: 'GET',
        url: '/ping',
        rawHeaders: {'host': 'localhost'},
      ),
      outgoing,
      baseUri: Uri.parse('http://localhost'),
    );

    expect(outgoing.finished, isTrue);
    expect(outgoing.statusCode, 200);
    expect(utf8.decode(outgoing.body.takeBytes()), 'pong');
  });

  test('portableRequestFromNode normalizes headers', () {
    final portable = portableRequestFromNode(
      _FakeIncoming(
        method: 'POST',
        url: '/x?y=1',
        rawHeaders: {
          'Content-Type': 'application/json',
          'X-List': ['a', 'b'],
        },
        remoteAddress: '9.9.9.9',
      ),
      baseUri: Uri.parse('http://api.test'),
    );

    expect(portable.method, 'POST');
    expect(portable.uri.path, '/x');
    expect(portable.uri.queryParameters['y'], '1');
    expect(portable.headers.get('content-type'), 'application/json');
    expect(portable.headers['x-list'], ['a', 'b']);
    expect(portable.remoteAddress, '9.9.9.9');
  });

  test('serveNode is VM-stubbed or binds on JS/Node', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    await engine.initialize();
    addTearDown(engine.close);

    try {
      final handle = await serveNode(
        engine,
        host: '127.0.0.1',
        port: 0,
        echo: false,
      );
      // JS/Node host selected the real runtime.
      addTearDown(() => handle.close(force: true));
      expect(handle.port, greaterThanOrEqualTo(0));
    } on UnsupportedError catch (e) {
      // Dart VM stub path.
      expect(e.message, contains('JavaScript/Node'));
    }
  });
}
