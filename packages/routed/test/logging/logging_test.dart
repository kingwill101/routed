import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('Logging integration', () {
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

    test('attaches request context to logger', () async {
      final engine = testEngine();
      engine.get('/hello', (ctx) async {
        final engineFromContainer = await ctx.container.make<Engine>();
        expect(identical(engineFromContainer, ctx.engine), isTrue);
        ctx.logger.info('handler invoked');
        return ctx.string('ok');
      });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/hello');
      response.assertStatus(200);

      expect(factory.contexts.length, greaterThan(0));
      final context = factory.contexts.first;
      expect(context['method'], equals('GET'));
      expect(context['path'], equals('/hello'));
      expect(context.containsKey('request_id'), isTrue);
      expect(
        factory.messages.any((m) => m.message.contains('handler invoked')),
        isTrue,
      );
    });

    test('logs unhandled errors through contextual logger', () async {
      final engine = testEngine();
      engine.get('/boom', (ctx) async {
        throw StateError('boom');
      });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/boom');
      response.assertStatus(HttpStatus.internalServerError);

      expect(
        factory.messages.any(
          (entry) =>
              entry.level == contextual.Level.error &&
              entry.message.contains('Unhandled exception'),
        ),
        isTrue,
      );
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
