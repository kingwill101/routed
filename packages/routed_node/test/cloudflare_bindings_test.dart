import 'package:routed_node/cloudflare.dart';
import 'package:routed_jobs/routed_jobs.dart';
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

  test('CloudflareJobQueue publishes Routed messages as JSON', () async {
    final queue = _FakeCloudflareQueue();
    final adapter = CloudflareJobQueue(queue);
    final message = JobMessage.fromJson({
      'id': 'job-1',
      'name': 'mail.welcome',
      'args': const <String, Object?>{'email': 'person@example.com'},
      'maxAttempts': 1,
      'notBefore': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 2))
          .toIso8601String(),
    });

    await adapter.publish(message);

    expect(queue.body, message.toJson());
    expect(queue.contentType, CloudflareQueueContentType.json);
    expect(queue.delaySeconds, greaterThanOrEqualTo(1));
  });

  test('opens an Ormed database from a native D1 binding', () async {
    final database = await openCloudflareD1(
      _FakeEnvironment(_FakeD1Database()),
      binding: 'DB',
      name: 'primary',
    );

    expect(database.name, 'primary');
    expect(database.driver.metadata.name, 'd1');
    await database.close();
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

final class _FakeEnvironment implements CloudflareEnvironment {
  _FakeEnvironment(this.database);

  final CloudflareD1Database database;

  @override
  CloudflareD1Database d1(String name) => database;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('binding is not used by this test');
  }
}

final class _FakeD1Database implements CloudflareD1Database {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('D1 operation is not used by this test');
  }
}

final class _FakeCloudflareQueue implements CloudflareQueue {
  Object? body;
  CloudflareQueueContentType? contentType;
  int? delaySeconds;

  @override
  Future<CloudflareQueueSendResult> send(
    Object? value, {
    CloudflareQueueContentType? contentType,
    int? delaySeconds,
  }) async {
    body = value;
    this.contentType = contentType;
    this.delaySeconds = delaySeconds;
    return const CloudflareQueueSendResult();
  }

  @override
  Future<CloudflareQueueSendResult> sendBatch(
    Iterable<CloudflareQueueMessage> messages, {
    int? delaySeconds,
  }) async => const CloudflareQueueSendResult();

  @override
  Future<CloudflareQueueMetrics> metrics() async =>
      const CloudflareQueueMetrics();
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
