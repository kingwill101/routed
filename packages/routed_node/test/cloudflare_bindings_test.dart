import 'package:routed_node/cloudflare.dart';
import 'package:test/test.dart';

import 'cloudflare_bindings_platform.dart';

void main() {
  test('Cloudflare API types are available from the public entrypoint', () {
    const result = CloudflareD1Result<int>(
      success: true,
      results: <int>[1, 2],
      meta: CloudflareD1Meta(
        rowsRead: 2,
        servedByColo: 'LHR',
        servedByPrimary: true,
      ),
    );

    expect(result.success, isTrue);
    expect(result.results, <int>[1, 2]);
    expect(result.meta?.rowsRead, 2);
    expect(result.meta?.servedByColo, 'LHR');
    expect(result.meta?.servedByPrimary, isTrue);

    final response = CloudflareResponse.json({'ok': true});
    expect(response.ok, isTrue);
    expect(response.headers['content-type'], 'application/json; charset=utf-8');
    expect(response.body, '{"ok":true}');
    expect(response.text(), '{"ok":true}');
    expect(response.json<Map<String, Object?>>()?['ok'], isTrue);
  });

  test('Cloudflare WebSocket upgrades stay host-neutral', () {
    final socket = _TestCloudflareWebSocket();
    final response = CloudflareResponse.webSocket(socket);

    expect(response.status, 101);
    expect(response.isWebSocketUpgrade, isTrue);
    expect(response.webSocket, same(socket));
  });

  test('popular Cloudflare binding values stay host-neutral', () async {
    final object = CloudflareR2Object(
      key: 'docs/readme.txt',
      size: 5,
      body: Stream.value(<int>[104, 101, 108, 108, 111]),
    );
    expect(await object.readAsString(), 'hello');

    const message = CloudflareQueueMessage(
      {'event': 'created'},
      contentType: CloudflareQueueContentType.json,
      delaySeconds: 10,
    );
    expect(message.body, {'event': 'created'});
    expect(message.contentType, CloudflareQueueContentType.json);
    expect(message.delaySeconds, 10);

    const listing = CloudflareR2ListOptions(prefix: 'docs/', limit: 20);
    expect(listing.prefix, 'docs/');
    expect(listing.limit, 20);
  });

  test('Cloudflare bindings fail clearly on non-JavaScript targets', () {
    if (cloudflareBindingsAreNative) return;
    expect(
      () => defineCloudflareDurableObjects(const {}),
      throwsUnsupportedError,
    );
    expect(
      () => createCloudflareRequest('https://example.test'),
      throwsUnsupportedError,
    );
    expect(() => cloudflareWebSocketPair(), throwsUnsupportedError);
  });
}

final class _TestCloudflareWebSocket implements CloudflareWebSocket {
  @override
  int get readyState => 1;

  @override
  void close([int? code, String? reason]) {}

  @override
  T? deserializeAttachment<T>({CloudflareJsonDecoder<T>? decode}) => null;

  @override
  void send(Object data) {}

  @override
  void serializeAttachment(Object? attachment) {}
}
