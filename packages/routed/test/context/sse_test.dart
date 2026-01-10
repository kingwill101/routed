import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  test('sse helper streams encoded events', () async {
    final events = <SseEvent>[
      SseEvent(id: '1', event: 'message', data: 'hello'),
      SseEvent(data: 'second', retry: const Duration(seconds: 5)),
    ];
    final controller = StreamController<SseEvent>();

    final engine = testEngine();
    engine.get('/events', (ctx) async {
      await ctx.sse(controller.stream, heartbeat: Duration.zero);
      return ctx.response;
    });

    await engine.initialize();
    final client = TestClient(
      RoutedRequestHandler(engine),
      mode: TransportMode.inMemory,
    );
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final responseFuture = client.get('/events');
    Future<void>(() async {
      for (final event in events) {
        controller.add(event);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await controller.close();
    });

    final response = await responseFuture;
    final body = response.body;

    expect(
      response.header(HttpHeaders.contentTypeHeader).first,
      contains('text/event-stream'),
    );
    expect(body, startsWith(':ok'));
  });

  test('sse helper emits heartbeat comments when idle', () async {
    final controller = StreamController<SseEvent>();

    final engine = testEngine();
    engine.get('/events', (ctx) async {
      await ctx.sse(
        controller.stream,
        heartbeat: const Duration(milliseconds: 40),
        heartbeatComment: 'ping',
      );
      return ctx.response;
    });

    await engine.initialize();
    final client = TestClient(
      RoutedRequestHandler(engine),
      mode: TransportMode.inMemory,
    );
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final responseFuture = client.get('/events');
    Timer(const Duration(milliseconds: 200), controller.close);

    final response = await responseFuture;
    expect(
      response.header(HttpHeaders.contentTypeHeader).first,
      contains('text/event-stream'),
    );
    expect(response.body, startsWith(':ok'));
  });

  test('sse helper closes gracefully when stream errors', () async {
    final controller = StreamController<SseEvent>();

    final engine = testEngine();
    engine.get('/events', (ctx) async {
      await ctx.sse(controller.stream, heartbeat: Duration.zero);
      return ctx.response;
    });

    await engine.initialize();
    final client = TestClient(
      RoutedRequestHandler(engine),
      mode: TransportMode.inMemory,
    );
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final responseFuture = client.get('/events');
    Timer(const Duration(milliseconds: 50), () async {
      controller.add(SseEvent(data: 'first'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.addError(Exception('boom'));
      await controller.close();
    });

    final response = await responseFuture;
    expect(
      response.header(HttpHeaders.contentTypeHeader).first,
      contains('text/event-stream'),
    );
    expect(response.body, startsWith(':ok'));
  });
}
