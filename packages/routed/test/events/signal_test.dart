import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('SignalHub', () {
    test('request lifecycle signals fire in order', () async {
      final engine = testEngine();
      engine.get('/ok', (ctx) => ctx.string('ok'));
      await engine.initialize();

      final manager = await engine.container.make<EventManager>();
      final hub = SignalHub(manager);
      engine.container.instance<SignalHub>(hub);

      final events = <String>[];
      hub.requests.started.connect((_) => events.add('started'));
      hub.requests.routeMatched.connect((_) => events.add('matched'));
      hub.requests.afterRouting.connect((_) => events.add('after'));
      hub.requests.finished.connect((_) => events.add('finished'));

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );

      final response = await client.get('/ok');
      response.assertStatus(200);
      expect(events, equals(['started', 'matched', 'after', 'finished']));

      await client.close();
      await engine.close();
    });

    test('SignalHub is available via request container', () async {
      final engine = testEngine();
      engine.get('/check', (ctx) async {
        final hub = ctx.container.get<SignalHub>();
        expect(hub.requests.started, isNotNull);
        return ctx.string('done');
      });
      await engine.initialize();
      final manager = await engine.container.make<EventManager>();
      engine.container.instance<SignalHub>(SignalHub(manager));

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );

      final res = await client.get('/check');
      res.assertStatus(200);

      await client.close();
      await engine.close();
    });

    test('handler errors surface as UnhandledSignalError', () async {
      final engine = testEngine();
      engine.get('/ok', (ctx) => ctx.string('ok'));
      await engine.initialize();

      final manager = await engine.container.make<EventManager>();
      final hub = SignalHub(manager);
      engine.container.instance<SignalHub>(hub);

      final completer = Completer<UnhandledSignalError>();
      final sub = manager.listen<UnhandledSignalError>(completer.complete);

      final handled = Completer<void>();
      hub.requests.routeMatched.connect((event) {
        handled.complete();
        throw StateError('boom');
      });

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );

      final res = await client.get('/ok');
      res.assertStatus(200);

      await handled.future;
      final error = await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      await client.close();
      await engine.close();

      expect(error.name, equals('routed.request.route_matched'));
      expect(error.error, isA<StateError>());
      expect(error.sender, isA<RequestSignalSender>());
      final sender = error.sender! as RequestSignalSender;
      expect(sender.context, isA<EngineContext>());
      expect(sender.route, isNotNull);
      expect(error.key, isNull);
    });

    test('signal handlers can scope to EngineContext sender', () async {
      final engine = testEngine();
      final completions = <String>[];
      engine.get('/one', (ctx) async {
        final hub = ctx.container.get<SignalHub>();
        late final SignalSubscription<RequestFinishedEvent> subscription;
        subscription = hub.requests.finished.connect(
          (_) async {
            completions.add('one');
            await subscription.cancel();
          },
          sender: ctx,
          key: 'ctx-hit',
        );
        return ctx.string('first');
      });
      engine.get('/two', (ctx) async {
        final hub = ctx.container.get<SignalHub>();
        late final SignalSubscription<RequestFinishedEvent> subscription;
        subscription = hub.requests.finished.connect((_) async {
          completions.add('two');
          await subscription.cancel();
        });
        return ctx.string('second');
      });
      await engine.initialize();
      final manager = await engine.container.make<EventManager>();
      engine.container.instance<SignalHub>(SignalHub(manager));

      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );

      final first = await client.get('/one');
      final second = await client.get('/two');
      first.assertStatus(200);
      second.assertStatus(200);
      expect(completions, equals(['one', 'two']));

      await client.close();
      await engine.close();
    });
  });

  group('Signal', () {
    late EventManager manager;

    setUp(() {
      manager = EventManager();
    });

    test('dispatch key replaces previous handler', () async {
      final signal = Signal<_StubEvent>(name: 'test.signal', manager: manager);

      final calls = <String>[];
      signal.connect((_) => calls.add('first'), key: 'analytics');
      signal.connect((_) => calls.add('second'), key: 'analytics');

      await signal.dispatch(_StubEvent('one'));

      expect(calls, equals(['second']));
    });

    test('subscription cancellation stops future dispatches', () async {
      final signal = Signal<_StubEvent>(name: 'test.signal', manager: manager);

      var counter = 0;
      final sub = signal.connect((_) => counter++);

      await signal.dispatch(_StubEvent('first'));
      expect(counter, equals(1));

      await sub.cancel();

      await signal.dispatch(_StubEvent('second'));
      expect(counter, equals(1));
    });

    test('sender filtering skips non matching senders', () async {
      final signal = Signal<_StubEvent>(name: 'test.signal', manager: manager);

      final sender = Object();
      var hits = 0;
      signal.connect((_) => hits++, sender: sender);

      await signal.dispatch(_StubEvent('ignored'), sender: Object());
      await signal.dispatch(_StubEvent('matched'), sender: sender);

      expect(hits, equals(1));
    });

    test('UnhandledSignalError surfaces key and sender metadata', () async {
      final signal = Signal<_StubEvent>(name: 'test.signal', manager: manager);

      final sender = Object();
      final errors = <UnhandledSignalError>[];
      manager.listen<UnhandledSignalError>(errors.add);

      signal.connect(
        (_) => throw StateError('boom'),
        key: 'audit',
        sender: sender,
      );

      await signal.dispatch(_StubEvent('fail'), sender: sender);
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.first.key, equals('audit'));
      expect(identical(errors.first.sender, sender), isTrue);
    });
  });
}

final class _StubEvent extends Event {
  _StubEvent(this.label);

  final String label;
}
