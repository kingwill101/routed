import 'dart:async';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Turbo logging context', () {
    TestClient? client;
    late _CapturingLoggerFactory factory;

    setUp(() {
      factory = _CapturingLoggerFactory();
      RoutedLogger.configureFactory(factory.create);
    });

    tearDown(() async {
      await client?.close();
      RoutedLogger.reset();
    });

    test('ctx.turbo enriches logging context for frame requests', () async {
      final engine = Engine();

      engine.get('/frame', (ctx) async {
        ctx.turbo; // triggers context enrichment
        ctx.logger.info('marker');
        return ctx.turboHtml('<turbo-frame id="hello"></turbo-frame>');
      });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get(
        '/frame',
        headers: {
          'Turbo-Frame': ['demo'],
          'X-Turbo-Request-Id': ['abc123'],
        },
      );
      response.assertStatus(HttpStatus.ok);
      // Give time for async logger listeners
      await Future<void>.delayed(Duration(milliseconds: 50));

      final marker = factory.messages.firstWhere(
        (entry) => entry.message.contains('marker'),
      );
      final markerContext = marker.context;
      expect(markerContext['hotwire.kind'], equals('frame'));
      expect(markerContext['hotwire.frame_id'], equals('demo'));
      expect(markerContext['hotwire.request_id'], equals('abc123'));
      expect(markerContext.containsKey('hotwire.stream_request'), isFalse);
    });

    test('ctx.turbo marks stream requests', () async {
      final engine = Engine();

      engine.post('/streams', (ctx) async {
        ctx.turbo;
        ctx.logger.info('stream handler');
        return ctx.turboStream('');
      });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.post(
        '/streams',
        '',
        headers: {
          'Accept': ['text/vnd.turbo-stream.html'],
        },
      );
      response.assertStatus(HttpStatus.ok);
      // Give time for async logger listeners
      await Future<void>.delayed(Duration(milliseconds: 50));

      final marker = factory.messages.firstWhere(
        (entry) => entry.message.contains('stream handler'),
      );
      final markerContext = marker.context;
      expect(markerContext['hotwire.kind'], equals('stream'));
      expect(markerContext['hotwire.stream_request'], isTrue);
      expect(markerContext.containsKey('hotwire.frame_id'), isFalse);
    });
  });
}

class _CapturingLoggerFactory {
  final List<_LogEntry> messages = [];

  contextual.Logger create(Map<String, Object?> context) {
    final logger = contextual.Logger()
      ..withContext({
        for (final entry in context.entries) entry.key: entry.value,
      });

    logger.setListener((entry) {
      messages.add(_LogEntry(entry.record.message, entry.record.context.all()));
    });

    return logger;
  }
}

class _LogEntry {
  _LogEntry(this.message, this.context);

  final String message;
  final Map<String, dynamic> context;
}
