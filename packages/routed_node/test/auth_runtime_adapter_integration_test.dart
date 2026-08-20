import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:routed_node/routed_node.dart';
import 'package:test/test.dart';

import '../../routed_auth/test/integration/support/runtime_auth_contract.dart';

const _origin = 'https://runtime.example';

final class _NodeIncoming implements NodeIncomingView {
  _NodeIncoming(this.source);

  final RuntimeAuthRequest source;

  @override
  String get method => source.method;

  @override
  String get url => source.path;

  @override
  Map<String, Object?> get rawHeaders => source.headers;

  @override
  Stream<List<int>> get body => source.body == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(source.body!));

  @override
  String get remoteAddress => '127.0.0.1';
}

final class _NodeOutgoing implements NodeServerResponseView {
  int statusCode = 200;
  final Map<String, List<String>> responseHeaders = <String, List<String>>{};
  final BytesBuilder body = BytesBuilder();
  bool _finished = false;

  @override
  bool get finished => _finished;

  @override
  void writeHead(int statusCode, Map<String, Object> headers) {
    this.statusCode = statusCode;
    headers.forEach((name, value) {
      responseHeaders[name] = value is Iterable
          ? value.map((item) => '$item').toList(growable: false)
          : <String>['$value'];
    });
  }

  @override
  void write(List<int> bytes) => body.add(bytes);

  @override
  void end([List<int>? bytes]) {
    if (bytes != null) body.add(bytes);
    _finished = true;
  }
}

final class _FetchRequest implements FetchRequestView {
  _FetchRequest(this.source);

  final RuntimeAuthRequest source;

  @override
  String get method => source.method;

  @override
  String get url => '$_origin${source.path}';

  @override
  Map<String, Object?> get rawHeaders => source.headers;

  @override
  Stream<List<int>> get body => source.body == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(source.body!));

  @override
  String get remoteAddress => '127.0.0.1';

  @override
  RoutedNodeContext? get hostContext => null;
}

void main() {
  test('Node portable adapter satisfies the auth runtime contract', () async {
    final engine = createRuntimeAuthEngine();
    await engine.initialize();
    addTearDown(engine.close);

    await verifyRuntimeAuthContract(
      origin: Uri.parse(_origin),
      send: (source) async {
        final outgoing = _NodeOutgoing();
        await dispatchNodeExchange(
          engine,
          _NodeIncoming(source),
          outgoing,
          baseUri: Uri.parse(_origin),
        );
        return RuntimeAuthResponse(
          statusCode: outgoing.statusCode,
          headers: outgoing.responseHeaders,
          body: utf8.decode(outgoing.body.takeBytes()),
        );
      },
    );
  });

  test('mocked Cloudflare Fetch edge satisfies the auth contract', () async {
    final engine = createRuntimeAuthEngine();
    await engine.initialize();
    addTearDown(engine.close);

    await verifyRuntimeAuthContract(
      origin: Uri.parse(_origin),
      send: (source) async {
        final response = await dispatchFetchExchange(
          engine,
          _FetchRequest(source),
          runtime: const RoutedNodeRuntimeInfo(
            runtime: RoutedNodeRuntime.cloudflare,
            capabilities: cloudflareCapabilities,
          ),
        );
        return RuntimeAuthResponse(
          statusCode: response.statusCode,
          headers: response.headers,
          body: await utf8.decodeStream(response.body),
        );
      },
    );
  });
}
