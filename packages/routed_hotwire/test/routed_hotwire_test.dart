import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('TurboRequestInfo', () {
    test('detects stream requests via Accept header', () {
      final info = TurboRequestInfo.fromHeaders({
        'accept': ['text/vnd.turbo-stream.html, text/html; q=0.8'],
      });

      expect(info.isStreamRequest, isTrue);
      expect(info.kind, TurboRequestKind.stream);
    });

    test('extracts frame id and classifies frame requests', () {
      final info = TurboRequestInfo.fromHeaders({
        'Turbo-Frame': ['sidebar'],
      });

      expect(info.frameId, 'sidebar');
      expect(info.kind, TurboRequestKind.frame);
    });

    test('defaults to standard when no Turbo headers are present', () {
      final info = TurboRequestInfo.fromHeaders({
        'accept': ['text/html'],
      });

      expect(info.kind, TurboRequestKind.standard);
      expect(info.isTurboVisit, isFalse);
    });

    test('captures turbo request identifier when present', () {
      final info = TurboRequestInfo.fromHeaders({
        'x-turbo-request-id': ['abc123 '],
      });

      expect(info.requestId, 'abc123');
    });
  });

  group('TurboResponse helpers', () {
    engineTest('turboStream sets correct headers and body', (
      engine,
      client,
    ) async {
      engine.post('/widgets', (ctx) {
        return ctx.turboStream(
          turboStreamAppend(target: 'widgets', html: '<div id="w1">A</div>'),
        );
      });

      final response = await client.post(
        '/widgets',
        '',
        headers: {
          'Accept': ['text/vnd.turbo-stream.html'],
        },
      );

      response
          .assertStatus(200)
          .assertHeaderContains('content-type', 'text/vnd.turbo-stream.html')
          .assertBodyContains('<turbo-stream action="append"');
    });

    engineTest('turboSeeOther replies with 303', (engine, client) async {
      engine.post('/rooms', (ctx) {
        return ctx.turboSeeOther('/rooms/next');
      });

      final response = await client.post('/rooms', '');

      response.assertStatus(303).assertHeader('location', '/rooms/next');
    });
  });

  group('TurboStreamHub', () {
    test('broadcast sends to active subscribers', () {
      final hub = TurboStreamHub();
      final active = _TestConnection();
      final closed = _TestConnection(closeCodeValue: 1000);

      hub.subscribe(active, ['room:a']);
      hub.subscribe(closed, ['room:a']);

      final fragment = turboStreamRemove(target: 'message_1');
      hub.broadcast('room:a', [fragment]);

      expect(active.messages, contains(fragment));
      expect(closed.messages, isEmpty);

      // closed connection should be removed after broadcast
      final second = turboStreamAppend(target: 'messages', html: '<div/>');
      hub.broadcast('room:a', [second]);

      expect(active.messages, contains(second));
      expect(closed.messages, isEmpty);
    });

    test('broadcast removes connections that throw', () {
      final hub = TurboStreamHub();
      final flaky = _TestConnection(throwOnSend: true);
      final healthy = _TestConnection();

      hub.subscribe(flaky, ['room:b']);
      hub.subscribe(healthy, ['room:b']);

      final fragment = turboStreamAppend(target: 'messages', html: '<p>hi</p>');
      hub.broadcast('room:b', [fragment]);

      expect(healthy.messages.length, 1);
      expect(flaky.messages, isEmpty);

      // second broadcast should only reach the healthy connection
      final second = turboStreamAppend(target: 'messages', html: '<p>two</p>');
      hub.broadcast('room:b', [second]);

      expect(healthy.messages.length, 2);
      expect(flaky.messages, isEmpty);
    });
  });

  group('Turbo stream builders', () {
    test('includes custom attributes on turbo stream tags', () {
      final fragment = turboStreamAppend(
        target: 'messages',
        html: '<div>Hi</div>',
        attributes: {'data-test': '1'},
      );

      expect(fragment, contains('data-test="1"'));
    });

    test('turboStreamRefresh emits request id when provided', () {
      final fragment = turboStreamRefresh(requestId: 'req-42');

      expect(fragment, contains('action="refresh"'));
      expect(fragment, contains('request-id="req-42"'));
      expect(fragment, isNot(contains('<template>')));
    });
  });

  group('Turbo stream naming', () {
    test('buildTurboStreamName flattens components', () {
      final name = buildTurboStreamName([
        'boards',
        1,
        ['messages', 'inbox'],
      ]);

      expect(name, 'boards:1:messages:inbox');
    });

    test('sign and verify round trip', () {
      final signed = signTurboStreamName(const ['notifications', 42]);

      expect(verifyTurboStreamName(signed), 'notifications:42');
    });

    test('rejects tampered signatures', () {
      final signed = signTurboStreamName(const ['rooms']);
      final parts = signed.split('--');
      final tampered =
          '${parts.first}--${parts.last.replaceRange(0, 4, 'AAAA')}';

      expect(verifyTurboStreamName(tampered), isNull);
    });

    test('renders turbo stream source tag', () {
      final tag = turboStreamSourceTag(
        streamables: const ['rooms', 'lobby'],
        dataAttributes: {'section': 'alpha'},
      );

      expect(tag, contains('turbo-cable-stream-source'));
      expect(tag, contains('data-section="alpha"'));
      expect(tag, contains('signed-stream-name='));
    });
  });
}

class _TestConnection implements TurboStreamConnection {
  _TestConnection({this.closeCodeValue, this.throwOnSend = false});

  final List<String> messages = [];
  final int? closeCodeValue;
  final bool throwOnSend;

  @override
  int? get closeCode => closeCodeValue;

  @override
  void send(String payload) {
    if (throwOnSend) throw StateError('socket closed');
    messages.add(payload);
  }
}
