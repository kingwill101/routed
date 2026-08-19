import 'dart:async';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/routed_core.dart';
import 'package:routed_logging/routed_logging.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

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

    test('typed channel definitions validate references before boot', () {
      final config = LoggingConfig(
        defaultChannel: 'stack',
        channels: {
          'stack': StackLoggingChannelConfig(
            name: 'stack',
            channels: const ['stdout'],
          ),
          'stdout': const StdoutLoggingChannelConfig(),
        },
      );

      expect(
        () => ConfigStore.fromProviders([LoggingServiceProvider(config)]),
        returnsNormally,
      );
    });

    test('typed channel definitions reject missing references', () {
      final config = LoggingConfig(
        defaultChannel: 'stack',
        channels: {
          'stack': StackLoggingChannelConfig(
            name: 'stack',
            channels: const ['missing'],
          ),
        },
      );

      expect(
        () => ConfigStore.fromProviders([LoggingServiceProvider(config)]),
        throwsA(
          isA<ConfigValidationException>().having(
            (error) => error.toString(),
            'message',
            contains('referenced channel must be configured'),
          ),
        ),
      );
    });

    test('respects logging.enabled false', () async {
      final engine = testEngine(loggingConfig: LoggingConfig(enabled: false));
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);

      expect(factory.messages, isEmpty);
    });

    test('errors_only logs only failures', () async {
      final engine = testEngine(loggingConfig: LoggingConfig(errorsOnly: true));
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
      final engine = testEngine(
        loggingConfig: LoggingConfig(level: contextual.Level.debug),
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

    test('logging configuration is fixed for the engine lifetime', () async {
      final engine = testEngine(loggingConfig: LoggingConfig(enabled: false));
      addTearDown(() async => await engine.close());
      engine.get('/ping', (ctx) => ctx.string('pong'));
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/ping');
      response.assertStatus(200);
      expect(factory.messages, isEmpty);
    });

    test('logging configuration is applied at startup', () async {
      final engine = testEngine(
        loggingConfig: LoggingConfig(level: contextual.Level.debug),
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

    test('extra fields and request headers appear in log context', () async {
      final engine = testEngine(
        loggingConfig: LoggingConfig(
          extraFields: {
            'service': 'api',
            'nested': {'tier': 'prod'},
          },
          requestHeaders: ['X-Correlation-ID'],
        ),
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

      final engine = testEngine(
        loggingConfig: LoggingConfig(
          defaultChannel: 'custom',
          channels: {
            'custom': CustomLoggingChannelConfig(
              name: 'custom',
              driver: 'capture',
            ),
          },
        ),
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
