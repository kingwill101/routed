import 'dart:async';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Route lifecycle events', () {
    test('publishes lifecycle events for 404 responses', () async {
      final engine = Engine();
      await engine.initialize();
      addTearDown(engine.close);

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final manager = await engine.container.make<EventManager>();
      final notFound = Completer<RouteNotFoundEvent>();
      final afterRouting = Completer<AfterRoutingEvent>();
      final requestFinished = Completer<RequestFinishedEvent>();

      manager.on<RouteNotFoundEvent>().listen((event) {
        if (!notFound.isCompleted) {
          notFound.complete(event);
        }
      });
      manager.on<AfterRoutingEvent>().listen((event) {
        if (!afterRouting.isCompleted) {
          afterRouting.complete(event);
        }
      });
      manager.on<RequestFinishedEvent>().listen((event) {
        if (!requestFinished.isCompleted) {
          requestFinished.complete(event);
        }
      });

      final response = await client.get('/missing');
      response.assertStatus(404);

      final notFoundEvent = await notFound.future.timeout(
        const Duration(seconds: 2),
      );
      final afterEvent = await afterRouting.future.timeout(
        const Duration(seconds: 2),
      );
      await requestFinished.future.timeout(const Duration(seconds: 2));

      expect(notFoundEvent.context.request.uri.path, equals('/missing'));
      expect(afterEvent.route, isNull);
      expect(notFoundEvent.context.response.statusCode, equals(404));
    });

    test('fires lifecycle events for successful routes', () async {
      final engine = Engine()..get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();
      addTearDown(engine.close);

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final manager = await engine.container.make<EventManager>();
      final events = <String>[];
      final subs = <StreamSubscription<Event>>[
        manager.on<BeforeRoutingEvent>().listen((_) => events.add('before')),
        manager.on<RequestStartedEvent>().listen((_) => events.add('started')),
        manager.on<RouteMatchedEvent>().listen((_) => events.add('matched')),
        manager.on<AfterRoutingEvent>().listen((_) => events.add('after')),
        manager.on<RequestFinishedEvent>().listen(
          (_) => events.add('finished'),
        ),
      ];
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
      });

      final response = await client.get('/ping');
      response.assertStatus(200);

      expect(
        events,
        equals(['before', 'started', 'matched', 'after', 'finished']),
      );
    });

    test('emits routing error events when handlers throw', () async {
      final engine = Engine()
        ..get('/boom', (ctx) {
          throw StateError('boom');
        });
      await engine.initialize();
      addTearDown(engine.close);

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final manager = await engine.container.make<EventManager>();
      final errorCompleter = Completer<RoutingErrorEvent>();
      final sub = manager.on<RoutingErrorEvent>().listen((event) {
        if (!errorCompleter.isCompleted) {
          errorCompleter.complete(event);
        }
      });
      addTearDown(sub.cancel);

      final response = await client.get('/boom');
      response.assertStatus(HttpStatus.internalServerError);

      final errorEvent = await errorCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(errorEvent.error, isA<StateError>());
    });

    test('active request tracking cleans up for 404 responses', () async {
      final engine = Engine();
      await engine.initialize();
      addTearDown(engine.close);

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      expect(engine.activeRequests, isEmpty);

      final response = await client.get('/nope');
      response.assertStatus(404);

      expect(engine.activeRequests, isEmpty);
    });

    test('runs global middleware for 404 responses', () async {
      var invoked = false;
      final engine = Engine(
        middlewares: [
          (ctx, next) async {
            invoked = true;
            ctx.response.headers.set('x-mw', 'hit');
            final result = await next();
            return result;
          },
        ],
      );
      await engine.initialize();
      addTearDown(engine.close);

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final response = await client.get('/ghost');
      response
        ..assertStatus(404)
        ..assertHeaderContains('x-mw', 'hit');

      expect(invoked, isTrue);
    });
  });

  group('WebSocket route events', () {
    late Engine engine;
    late HttpServer server;

    setUp(() async {
      engine = Engine();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => engine.handleRequest(request));
    });

    tearDown(() async {
      await server.close();
      await engine.close();
    });

    test('fires lifecycle events for WebSocket routes', () async {
      final manager = await engine.container.make<EventManager>();
      final events = <String>[];
      final subs = <StreamSubscription<Event>>[
        manager.on<BeforeRoutingEvent>().listen((_) => events.add('before')),
        manager.on<RequestStartedEvent>().listen((_) => events.add('started')),
        manager.on<RouteMatchedEvent>().listen((_) => events.add('matched')),
        manager.on<AfterRoutingEvent>().listen((_) => events.add('after')),
        manager.on<RequestFinishedEvent>().listen(
          (_) => events.add('finished'),
        ),
      ];
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
      });

      engine.ws('/socket', _NoopWebSocketHandler());
      final ws = await WebSocket.connect(
        'ws://localhost:${server.port}/socket',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await ws.close();

      expect(events, containsAllInOrder(['before', 'started', 'matched']));
      expect(events, contains('after'));
      expect(events, contains('finished'));
    });

    test('publishes routing error events for WebSocket failures', () async {
      final manager = await engine.container.make<EventManager>();
      final routingError = Completer<RoutingErrorEvent>();
      final sub = manager.on<RoutingErrorEvent>().listen((event) {
        if (!routingError.isCompleted) {
          routingError.complete(event);
        }
      });
      addTearDown(sub.cancel);

      engine.ws('/boom', _ThrowingWebSocketHandler());
      final ws = await WebSocket.connect('ws://localhost:${server.port}/boom');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await ws.close();

      final event = await routingError.future.timeout(
        const Duration(seconds: 2),
      );
      expect(event.route?.path, equals('/boom'));
      expect(event.error, isA<StateError>());
    });
  });
}

class _NoopWebSocketHandler extends WebSocketHandler {
  @override
  Future<void> onClose(WebSocketContext context) async {}

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {}

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {}

  @override
  Future<void> onOpen(WebSocketContext context) async {}
}

class _ThrowingWebSocketHandler extends WebSocketHandler {
  @override
  Future<void> onClose(WebSocketContext context) async {}

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {}

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {}

  @override
  Future<void> onOpen(WebSocketContext context) async {
    throw StateError('boom');
  }
}
