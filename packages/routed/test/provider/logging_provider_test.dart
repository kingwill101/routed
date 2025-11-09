import 'dart:async';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('LoggingServiceProvider', () {
    TestClient? client;
    late _CapturingLoggerFactory factory;

    setUp(() {
      factory = _CapturingLoggerFactory();
      RoutedLogger.configureFactory(factory.create);
    });

    tearDown(() async {
      RoutedLogger.reset();
      await client?.close();
    });

    test('respects logging.enabled false', () async {
      final engine = Engine(
        configItems: {
          'logging': {'enabled': false},
        },
      );
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);

      expect(factory.messages, isEmpty);
    });

    test('errors_only logs only failures', () async {
      final engine = Engine(
        configItems: {
          'logging': {'errors_only': true},
        },
      );
      addTearDown(() async => await engine.close());
      engine
        ..get('/ok', (ctx) => ctx.string('ok'))
        ..get('/boom', (ctx) => throw StateError('boom'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final ok = await client!.get('/ok');
      ok.assertStatus(200);
      expect(factory.messages, isEmpty);

      final boom = await client!.get('/boom');
      boom.assertStatus(HttpStatus.internalServerError);

      expect(
        factory.messages.any((entry) => entry.level == contextual.Level.error),
        isTrue,
      );
    });

    test('level debug uses debug channel for successful requests', () async {
      final engine = Engine(
        configItems: {
          'logging': {'level': 'debug'},
        },
      );
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);

      expect(
        factory.messages.any((entry) => entry.level == contextual.Level.debug),
        isTrue,
      );
    });

    test('withLogging helper mutates config', () async {
      final engine = Engine(options: [withLogging(enabled: false)]);
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);
      expect(factory.messages, isEmpty);
    });

    test('config reload applies logging changes', () async {
      final engine = Engine(
        configItems: {
          'logging': {'enabled': false},
        },
      );
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('logging', {'enabled': true, 'level': 'debug'});
      await engine.replaceConfig(override);
      await Future<void>.delayed(Duration.zero);

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);

      expect(
        factory.messages.any((entry) => entry.level == contextual.Level.debug),
        isTrue,
      );
    });

    test('extra fields and request headers appear in log context', () async {
      final engine = Engine(
        configItems: {
          'logging': {
            'extra_fields': {
              'service': 'api',
              'nested': {'tier': 'prod'},
            },
            'request_headers': ['X-Correlation-ID'],
          },
        },
      );
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get(
        '/ping',
        headers: {
          'X-Correlation-ID': ['corr-123'],
        },
      );
      response.assertStatus(200);

      expect(factory.contexts, isNotEmpty);
      final context = factory.contexts.last;
      expect(context['service'], equals('api'));
      expect(context['nested'], equals({'tier': 'prod'}));
      expect(context['header_x_correlation_id'], equals('corr-123'));
    });

    test('custom log driver from registry is used', () async {
      RoutedLogger.reset();

      final engine = Engine(
        configItems: {
          'logging': {
            'default': 'custom',
            'channels': {
              'custom': {'driver': 'capture'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());

      final registry = engine.container.get<LogDriverRegistry>();
      final capture = _BufferLogDriver();
      registry.register('capture', (ctx) => capture, override: true);

      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);

      expect(capture.entries, isNotEmpty);
      expect(capture.entries.any((entry) => entry.contains('/ping')), isTrue);
    });
  });
}

class _CapturingLoggerFactory {
  final List<Map<String, Object?>> contexts = [];
  final List<_LogEntry> messages = [];

  contextual.Logger create(Map<String, Object?> context) {
    final captured = Map<String, Object?>.from(context);
    contexts.add(captured);

    final logger = contextual.Logger()
      ..withContext({
        for (final entry in captured.entries) entry.key: entry.value,
      });

    logger.setListener((entry) {
      messages.add(
        _LogEntry(
          entry.record.level,
          entry.record.message,
          entry.record.context.all(),
        ),
      );
    });

    return logger;
  }
}

class _LogEntry {
  _LogEntry(this.level, this.message, this.context);

  final contextual.Level level;
  final String message;
  final Map<String, dynamic> context;
}

class _BufferLogDriver extends contextual.LogDriver {
  _BufferLogDriver() : super('buffer');

  final List<String> entries = [];

  @override
  Future<void> log(contextual.LogEntry entry) async {
    entries.add(entry.message);
  }
}
