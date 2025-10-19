import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:routed/routed.dart';
import 'package:server_testing/mock.dart';
import 'package:test/test.dart';

EngineContext _buildContext(BytesBuilder body) {
  final mockRequest = setupRequest('GET', '/events');
  final mockResponse = setupResponse(body: body);

  final responseDone = Completer<void>();
  when(mockResponse.flush()).thenAnswer((_) async {});
  when(mockResponse.done).thenAnswer((_) => responseDone.future);
  when(mockResponse.close()).thenAnswer((_) async {
    if (!responseDone.isCompleted) {
      responseDone.complete();
    }
  });

  final request = Request(mockRequest, const {}, EngineConfig());
  final response = Response(mockResponse);
  return EngineContext(
    request: request,
    response: response,
    container: Container(),
  );
}

void main() {
  test('sse helper streams encoded events', () async {
    final events = <SseEvent>[
      SseEvent(id: '1', event: 'message', data: 'hello'),
      SseEvent(data: 'second', retry: const Duration(seconds: 5)),
    ];

    final buffer = BytesBuilder();
    final ctx = _buildContext(buffer);

    await ctx.sse(Stream.fromIterable(events), heartbeat: Duration.zero);

    final codec = SseCodec();
    final expected = events.map(codec.encode).join();
    final body = utf8.decode(buffer.takeBytes());

    expect(body, startsWith(':ok'));
    final trimmed = body.replaceFirst(':ok\n\n', '');
    expect(trimmed, expected);
    expect(trimmed, contains('retry: 5000'));
  });

  test('sse helper emits heartbeat comments when idle', () async {
    final controller = StreamController<SseEvent>();
    final buffer = BytesBuilder();
    final ctx = _buildContext(buffer);

    Timer(const Duration(milliseconds: 120), controller.close);

    await ctx.sse(
      controller.stream,
      heartbeat: const Duration(milliseconds: 40),
      heartbeatComment: 'ping',
    );

    final body = utf8.decode(buffer.takeBytes());
    expect(body.contains(':ping'), isTrue);
  });

  test('sse helper closes gracefully when stream errors', () async {
    final controller = StreamController<SseEvent>();
    final buffer = BytesBuilder();
    final ctx = _buildContext(buffer);

    Timer(const Duration(milliseconds: 50), () {
      controller.add(SseEvent(data: 'first'));
      controller.addError(Exception('boom'));
      controller.close();
    });

    await ctx.sse(controller.stream, heartbeat: Duration.zero);

    final body = utf8.decode(buffer.takeBytes());
    expect(body, contains('data: first'));
  });
}
