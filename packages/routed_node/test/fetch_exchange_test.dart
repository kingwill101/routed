import 'dart:async';
import 'dart:convert';

import 'package:routed_core/routed_core.dart';
import 'package:routed_node/routed_node.dart';
import 'package:test/test.dart';

final class _FetchRequest implements FetchRequestView {
  _FetchRequest({this.bodyBytes = const []});

  final List<int> bodyBytes;

  @override
  String get method => 'POST';

  @override
  String get url => 'https://example.test/items?draft=true';

  @override
  Map<String, Object?> get rawHeaders => {
    'content-type': 'application/json',
    'x-list': ['a', 'b'],
  };

  @override
  Stream<List<int>> get body => Stream.value(bodyBytes);

  @override
  String? get remoteAddress => '127.0.0.1';

  @override
  RoutedNodeContext? get hostContext => null;
}

void main() {
  test('Fetch request converts to PortableRequest', () async {
    final portable = portableRequestFromFetch(
      _FetchRequest(bodyBytes: utf8.encode('{"ok":true}')),
    );

    expect(portable.method, 'POST');
    expect(portable.uri.path, '/items');
    expect(portable.uri.queryParameters['draft'], 'true');
    expect(portable.headers['x-list'], ['a', 'b']);
    expect(await utf8.decodeStream(portable.body), '{"ok":true}');
  });

  test('buffered Fetch exchange preserves response headers and body', () async {
    final engine = Engine(providers: Engine.defaultProviders);
    engine.post('/items', (ctx) {
      ctx.response.addHeader('X-Test', 'one');
      return ctx.string('created', statusCode: 201);
    });
    await engine.initialize();
    addTearDown(engine.close);

    final response = await dispatchFetchExchange(
      engine,
      _FetchRequest(),
      runtime: const RoutedNodeRuntimeInfo(
        runtime: RoutedNodeRuntime.cloudflare,
        capabilities: cloudflareCapabilities,
      ),
    );

    expect(response.statusCode, 201);
    expect(response.headers.values.expand((v) => v), contains('one'));
    expect(await utf8.decodeStream(response.body), 'created');
  });
}
