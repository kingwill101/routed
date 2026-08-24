import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:routed_core/routed_core.dart';
import 'package:routed_observability/routed_observability.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

void main() {
  group('ObservabilityServiceProvider', () {
    test('tracing middleware attaches span context', () async {
      final engine = testEngine(
        observabilityConfig: ObservabilityConfig(
          tracing: ObservabilityTracingConfig(
            enabled: true,
            exporter: 'console',
          ),
          metrics: ObservabilityMetricsConfig(),
          health: ObservabilityHealthConfig(enabled: false),
        ),
      );
      addTearDown(() async => engine.close());

      engine.get('/trace', (ctx) {
        final spanContext = dotel.Context.current.spanContext;
        final traceId = spanContext?.traceId.hexString ?? '';
        ctx.response.write(traceId);
        return ctx.response;
      });

      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      final response = await client.get('/trace');
      response.assertStatus(200);

      const zeroTraceId = '00000000000000000000000000000000';
      final traceId = response.body.trim();
      expect(traceId.length, equals(32));
      expect(traceId, isNot(zeroTraceId));
    });

    test('metrics endpoint exposes request counters', () async {
      final engine = testEngine(
        observabilityConfig: ObservabilityConfig(
          tracing: ObservabilityTracingConfig(),
          metrics: ObservabilityMetricsConfig(enabled: true),
          health: ObservabilityHealthConfig(enabled: false),
        ),
      );
      addTearDown(() async => engine.close());

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
      final engine = testEngine(
        observabilityConfig: ObservabilityConfig(
          tracing: ObservabilityTracingConfig(),
          metrics: ObservabilityMetricsConfig(),
          health: ObservabilityHealthConfig(),
        ),
      );
      addTearDown(() async => engine.close());

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
      final readinessJson = readiness.json() as Map<String, Object?>;
      expect(readinessJson['ok'], isFalse);
      final checks = readinessJson['checks']! as Map<String, Object?>;
      expect(checks.containsKey('database'), isTrue);
      final database = checks['database']! as Map<String, Object?>;
      expect(database['reason'], equals('offline'));

      final liveness = await client.get('/livez');
      liveness.assertStatus(200);
      final livenessJson = liveness.json() as Map<String, Object?>;
      expect(livenessJson['ok'], isTrue);
    });

    test('readiness reports unhealthy during graceful shutdown', () async {
      final engine = testEngine(
        config: EngineConfig(
          shutdown: const ShutdownConfig(
            enabled: true,
            gracePeriod: Duration(seconds: 20),
            forceAfter: Duration(minutes: 1),
            exitCode: 0,
            notifyReadiness: true,
            signals: {ProcessSignal.sigint, ProcessSignal.sigterm},
          ),
        ),
        observabilityConfig: ObservabilityConfig(
          tracing: ObservabilityTracingConfig(),
          metrics: ObservabilityMetricsConfig(),
          health: ObservabilityHealthConfig(),
        ),
      );
      addTearDown(() async => engine.close());

      await engine.initialize();

      final handler = RoutedRequestHandler(engine);
      final client = TestClient(handler, mode: TransportMode.ephemeralServer);
      addTearDown(() async => client.close());

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

    test('rejects invalid observability configuration before boot', () {
      final engine = testEngine(
        observabilityConfig: ObservabilityConfig(
          tracing: ObservabilityTracingConfig(exporter: 'unknown'),
        ),
      );
      addTearDown(engine.close);

      return expectLater(
        engine.initialize(),
        throwsA(isA<ConfigValidationException>()),
      );
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
