import 'dart:io';

import 'package:contextual/contextual.dart';
import 'package:routed/src/logging/channel_drivers.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('SingleFileLogDriver', () {
    late Directory tempDir;
    late String logFilePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('routed_log_test_');
      logFilePath = '${tempDir.path}/app.log';
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates parent directories if they do not exist', () async {
      final nestedPath = '${tempDir.path}/nested/deep/logs/app.log';
      final driver = SingleFileLogDriver(nestedPath);

      final entry = LogEntry(
        LogRecord(
          message: 'test message',
          level: Level.info,
          time: DateTime.now(),
        ),
        'test message',
      );

      await driver.log(entry);
      await driver.performShutdown();

      expect(File(nestedPath).existsSync(), isTrue);
    });

    test('writes log messages to file', () async {
      final driver = SingleFileLogDriver(logFilePath);

      final entry = LogEntry(
        LogRecord(
          message: 'Hello from test',
          level: Level.info,
          time: DateTime.now(),
        ),
        'Hello from test',
      );

      await driver.log(entry);
      await driver.performShutdown();

      final content = File(logFilePath).readAsStringSync();
      expect(content, contains('Hello from test'));
    });

    test('does not include ANSI escape codes in file output', () async {
      final driver = SingleFileLogDriver(logFilePath);

      // Log multiple levels to ensure none include ANSI codes
      final levels = [Level.debug, Level.info, Level.warning, Level.error];

      for (final level in levels) {
        final ctx = Context({'key': 'value'});
        final entry = LogEntry(
          LogRecord(
            message: 'Test message at ${level.name}',
            level: level,
            time: DateTime.now(),
            context: ctx,
          ),
          '\x1B[32mPretty formatted message\x1B[0m', // Simulating pretty output
        );

        await driver.log(entry);
      }

      await driver.performShutdown();

      final content = File(logFilePath).readAsStringSync();

      // ANSI escape codes start with ESC (0x1B or \x1B) followed by [
      // Common patterns: \x1B[32m (green), \x1B[0m (reset), etc.
      final ansiPattern = RegExp(r'\x1B\[[\d;]*m');

      expect(
        ansiPattern.hasMatch(content),
        isFalse,
        reason:
            'File log should not contain ANSI escape codes.\nContent:\n$content',
      );

      // Verify the actual messages are still present
      expect(content, contains('Test message at debug'));
      expect(content, contains('Test message at info'));
      expect(content, contains('Test message at warning'));
      expect(content, contains('Test message at error'));
    });

    test('uses PlainTextLogFormatter by default', () async {
      final driver = SingleFileLogDriver(logFilePath);

      final time = DateTime(2026, 1, 18, 12, 0, 0);
      final ctx = Context({'request_id': 'abc123'});
      final entry = LogEntry(
        LogRecord(
          message: 'Formatted test',
          level: Level.info,
          time: time,
          context: ctx,
        ),
        'ignored entry message',
      );

      await driver.log(entry);
      await driver.performShutdown();

      final content = File(logFilePath).readAsStringSync();

      // PlainTextLogFormatter uses logfmt style: time=... level=... msg=...
      expect(content, contains('level=info'));
      expect(content, contains('msg="Formatted test"'));
      expect(content, contains('request_id=abc123'));
    });

    test('allows custom formatter', () async {
      final customFormatter = _CustomFormatter();
      final driver = SingleFileLogDriver(
        logFilePath,
        formatter: customFormatter,
      );

      final entry = LogEntry(
        LogRecord(
          message: 'Custom format test',
          level: Level.warning,
          time: DateTime.now(),
        ),
        'ignored',
      );

      await driver.log(entry);
      await driver.performShutdown();

      final content = File(logFilePath).readAsStringSync();
      expect(content, contains('[CUSTOM] Custom format test'));
    });

    test('appends to existing file', () async {
      // Write initial content
      File(logFilePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('Existing content\n');

      final driver = SingleFileLogDriver(logFilePath);

      final entry = LogEntry(
        LogRecord(
          message: 'New message',
          level: Level.info,
          time: DateTime.now(),
        ),
        'New message',
      );

      await driver.log(entry);
      await driver.performShutdown();

      final content = File(logFilePath).readAsStringSync();
      expect(content, contains('Existing content'));
      expect(content, contains('New message'));
    });
  });

  group('NullLogDriver', () {
    test('drops all messages', () async {
      final driver = NullLogDriver();

      final entry = LogEntry(
        LogRecord(
          message: 'This should be dropped',
          level: Level.info,
          time: DateTime.now(),
        ),
        'This should be dropped',
      );

      // Should not throw
      await driver.log(entry);
    });
  });

  group('StderrLogDriver', () {
    test('logs to stderr without throwing', () async {
      final driver = StderrLogDriver();

      final entry = LogEntry(
        LogRecord(
          message: 'Stderr test message',
          level: Level.error,
          time: DateTime.now(),
        ),
        'Stderr test message',
      );

      // Should not throw
      await driver.log(entry);
    });
  });
}

class _CustomFormatter extends LogMessageFormatter {
  _CustomFormatter() : super();

  @override
  String format(LogRecord record) {
    return '[CUSTOM] ${record.message}';
  }
}
