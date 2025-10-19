import 'dart:async';

import 'package:opentelemetry/api.dart' as otel;
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('ObservabilityServiceProvider', () {
    test('tracing middleware attaches span context', () async {
      final engine = Engine(
        configItems: {
          'observability': {
            'tracing': {'enabled': true, 'exporter': 'console'},
            'metrics': {'enabled': false},
            'health': {'enabled': false},
          },
        },
      );
      addTearDown(() async => await engine.close());

      engine.get('/trace', (ctx) {
        final span = otel.spanFromContext(otel.Context.current);
        ctx.response.write(span.spanContext.traceId.get());
        return ctx.response;
      });

      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      final response = await client.get('/trace');
      response.assertStatus(200);

      final traceId = response.body.trim();
      expect(traceId, isNotEmpty);
      expect(traceId, isNot(otel.TraceId.invalid().get()));
    });

    test('metrics endpoint exposes request counters', () async {
      final engine = Engine(
        configItems: {
          'observability': {
            'tracing': {'enabled': false},
            'metrics': {'enabled': true, 'path': '/metrics'},
            'health': {'enabled': false},
          },
        },
      );
      addTearDown(() async => await engine.close());

      engine.get('/hello', (ctx) => ctx.string('ok'));
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));

      await client.get('/hello');
      final metrics = await client.get('/metrics');
      expect(metrics.statusCode, equals(200), reason: metrics.body);
      expect(
        metrics.body,
        contains(
          'routed_requests_total{method="GET",route="/hello",status="200"} 1',
        ),
      );
    });

    test('health endpoint supports custom readiness checks', () async {
      final engine = Engine(
        configItems: {
          'observability': {
            'tracing': {'enabled': false},
            'metrics': {'enabled': false},
            'health': {'enabled': true},
          },
        },
      );
      addTearDown(() async => await engine.close());

      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      final health = await engine.container.make<HealthService>();
      health.registerReadinessCheck(
        'database',
        () => HealthCheckResult.failure({'reason': 'offline'}),
      );

      final client = TestClient(RoutedRequestHandler(engine));

      final readiness = await client.get('/readyz');
      expect(readiness.statusCode, equals(503), reason: readiness.body);
      expect(readiness.json()['ok'], isFalse);
      final checks = readiness.json()['checks'] as Map<String, dynamic>;
      expect(checks.containsKey('database'), isTrue);
      expect(checks['database']['reason'], equals('offline'));

      final liveness = await client.get('/livez');
      liveness.assertStatus(200);
      expect(liveness.json()['ok'], isTrue);
    });

    test('readiness reports unhealthy during graceful shutdown', () async {
      final engine = Engine(
        configItems: {
          'observability': {
            'tracing': {'enabled': false},
            'metrics': {'enabled': false},
            'health': {'enabled': true},
          },
        },
      );
      addTearDown(() async => await engine.close());

      await engine.initialize();

      final handler = RoutedRequestHandler(engine);
      final client = TestClient(handler, mode: TransportMode.ephemeralServer);
      addTearDown(() async => await client.close());

      // Kick the server to ensure the shutdown controller is registered.
      final initialResponse = await client.get('/readyz');
      initialResponse.assertStatus(200);

      final health = await engine.container.make<HealthService>();
      final initial = await health.readiness();
      expect(initial.ok, isTrue);

      final controller = await _waitForShutdownController(engine);
      final shutdownFuture = controller.trigger();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final draining = await health.readiness();
      expect(draining.ok, isFalse);

      await shutdownFuture;
    });
  });
}

Future<ShutdownController> _waitForShutdownController(Engine engine) async {
  for (var i = 0; i < 200; i++) {
    final controller = engine.shutdownController;
    if (controller != null) {
      return controller;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Shutdown controller was not registered.');
}
