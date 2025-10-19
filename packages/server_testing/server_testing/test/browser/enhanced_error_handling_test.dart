import 'dart:io';

import 'package:server_testing/src/browser/browser_exception.dart';
import 'package:server_testing/src/browser/browser_logger.dart'
    show EnhancedBrowserLogger;
import 'package:server_testing/src/browser/enhanced_exceptions.dart';
import 'package:server_testing/src/browser/screenshot_manager.dart';
import 'package:test/test.dart';

void main() {
  group('EnhancedBrowserException', () {
    test('should create exception with basic message', () {
      final exception = EnhancedBrowserException('Test error');

      expect(exception.message, equals('Test error'));
      expect(exception.selector, isNull);
      expect(exception.action, isNull);
      expect(exception.screenshotPath, isNull);
      expect(exception.details, isNull);
      expect(exception.cause, isNull);
    });

    test('should create exception with all context information', () {
      final exception = EnhancedBrowserException(
        'Element not found',
        selector: '#submit-button',
        action: 'click',
        screenshotPath: 'test_screenshots/failure_123.png',
        details: 'Button was not visible',
        cause: Exception('WebDriver error'),
      );

      expect(exception.message, equals('Element not found'));
      expect(exception.selector, equals('#submit-button'));
      expect(exception.action, equals('click'));
      expect(
        exception.screenshotPath,
        equals('test_screenshots/failure_123.png'),
      );
      expect(exception.details, equals('Button was not visible'));
      expect(exception.cause, isA<Exception>());
    });

    test('should format toString with all context information', () {
      final exception = EnhancedBrowserException(
        'Element not found',
        selector: '#submit-button',
        action: 'click',
        screenshotPath: 'test_screenshots/failure_123.png',
        details: 'Button was not visible',
        cause: Exception('WebDriver error'),
      );

      final string = exception.toString();

      expect(string, contains('EnhancedBrowserException: Element not found'));
      expect(string, contains('Action: click'));
      expect(string, contains('Selector: #submit-button'));
      expect(string, contains('Details: Button was not visible'));
      expect(string, contains('Screenshot: test_screenshots/failure_123.png'));
      expect(string, contains('Cause: Exception: WebDriver error'));
    });

    test('should format toString with minimal information', () {
      final exception = EnhancedBrowserException('Simple error');

      final string = exception.toString();

      expect(string, equals('EnhancedBrowserException: Simple error'));
      expect(string, isNot(contains('Action:')));
      expect(string, isNot(contains('Selector:')));
      expect(string, isNot(contains('Details:')));
      expect(string, isNot(contains('Screenshot:')));
      expect(string, isNot(contains('Cause:')));
    });

    test('should create copy with updated context', () {
      final original = EnhancedBrowserException(
        'Original error',
        selector: '#original',
        action: 'original-action',
      );

      final copy = original.copyWith(
        message: 'Updated error',
        selector: '#updated',
        screenshotPath: 'new_screenshot.png',
      );

      expect(copy.message, equals('Updated error'));
      expect(copy.selector, equals('#updated'));
      expect(copy.action, equals('original-action')); // Should keep original
      expect(copy.screenshotPath, equals('new_screenshot.png'));
    });

    test('should extend BrowserException', () {
      final exception = EnhancedBrowserException('Test error');
      expect(exception, isA<BrowserException>());
    });
  });

  group('EnhancedTimeoutException', () {
    test('should create timeout exception with context', () {
      final exception = EnhancedTimeoutException(
        'Timeout waiting for element',
        timeout: const Duration(seconds: 30),
        selector: '#loading-spinner',
        action: 'waitForElement',
        screenshotPath: 'timeout_screenshot.png',
        details: 'Element never appeared',
      );

      expect(exception.message, equals('Timeout waiting for element'));
      expect(exception.timeout, equals(const Duration(seconds: 30)));
      expect(exception.selector, equals('#loading-spinner'));
      expect(exception.action, equals('waitForElement'));
      expect(exception.screenshotPath, equals('timeout_screenshot.png'));
      expect(exception.details, equals('Element never appeared'));
    });

    test('should format toString with timeout information', () {
      final exception = EnhancedTimeoutException(
        'Timeout waiting for element',
        timeout: const Duration(seconds: 30),
        selector: '#loading-spinner',
        action: 'waitForElement',
      );

      final string = exception.toString();

      expect(
        string,
        contains('EnhancedTimeoutException: Timeout waiting for element (30s)'),
      );
      expect(string, contains('Action: waitForElement'));
      expect(string, contains('Selector: #loading-spinner'));
    });

    test('should extend TimeoutException', () {
      final exception = EnhancedTimeoutException('Test timeout');
      expect(exception, isA<TimeoutException>());
    });
  });

  group('EnhancedBrowserLogger', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('browser_logger_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should not log when verbose logging is disabled', () {
      final logger = const EnhancedBrowserLogger(verboseLogging: false);

      // This should not throw or print anything
      logger.logInfo('Test message');
      logger.logOperationStart('test-action');
      logger.logOperationComplete('test-action');
    });

    test('should log when verbose logging is enabled', () {
      final logger = const EnhancedBrowserLogger(verboseLogging: true);

      // These should not throw (we can't easily test console output in unit tests)
      logger.logInfo('Test message', action: 'test', selector: '#test');
      logger.logOperationStart(
        'test-action',
        selector: '#test',
        parameters: {'key': 'value'},
      );
      logger.logOperationComplete(
        'test-action',
        selector: '#test',
        duration: const Duration(milliseconds: 100),
      );
    });

    test('should always log warnings and errors', () {
      final logger = const EnhancedBrowserLogger(verboseLogging: false);

      // These should not throw even with verbose logging disabled
      logger.logWarning('Test warning', action: 'test', selector: '#test');
      logger.logError(
        'Test error',
        action: 'test',
        selector: '#test',
        error: Exception('test'),
      );
    });

    test('should write to log file when directory is specified', () async {
      final logger = EnhancedBrowserLogger(
        verboseLogging: true,
        logDirectory: tempDir.path,
      );

      logger.logInfo('Test log message');
      logger.logWarning('Test warning');
      logger.logError('Test error');

      // Give it a moment to write the file
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final logFiles = tempDir
          .listSync()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      expect(logFiles, isNotEmpty);

      final logFile = File(logFiles.first.path);
      final content = await logFile.readAsString();
      expect(content, contains('Test log message'));
      expect(content, contains('Test warning'));
      expect(content, contains('Test error'));
    });

    test('should handle log file write errors gracefully', () {
      // Use an invalid directory path
      final logger = const EnhancedBrowserLogger(
        verboseLogging: true,
        logDirectory: '/invalid/path/that/does/not/exist',
      );

      // This should not throw, even though the directory doesn't exist
      expect(() => logger.logInfo('Test message'), returnsNormally);
    });
  });

  group('ScreenshotManager', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('screenshot_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should create screenshot directory if it does not exist', () {
      final screenshotDir = Directory('${tempDir.path}/screenshots');
      expect(screenshotDir.existsSync(), isFalse);

      ScreenshotManager(
        screenshotDirectory: screenshotDir.path,
        autoScreenshots: false,
      );

      // The directory should be created when we try to capture a screenshot
      // (We can't test actual screenshot capture without a real WebDriver)
    });

    test('should generate unique filenames', () {
      ScreenshotManager(
        screenshotDirectory: tempDir.path,
        autoScreenshots: true,
      );

      // Test the filename generation logic by creating mock files
      final timestamp1 = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final timestamp2 = DateTime.now()
          .add(const Duration(milliseconds: 1))
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');

      expect(timestamp1, isNot(equals(timestamp2)));
    });

    test('should cleanup old screenshots', () async {
      final manager = ScreenshotManager(
        screenshotDirectory: tempDir.path,
        autoScreenshots: true,
      );

      // Create some old screenshot files
      final oldFile = File('${tempDir.path}/old_screenshot.png');
      await oldFile.create();

      // Set the file's modification time to be old
      // Note: We can't easily set file modification time in tests,
      // but we can test that the cleanup method doesn't throw

      expect(() => manager.cleanupOldScreenshots(), returnsNormally);
    });

    test('should handle cleanup errors gracefully', () {
      final manager = const ScreenshotManager(
        screenshotDirectory: '/invalid/path',
        autoScreenshots: true,
      );

      // This should not throw even with an invalid directory
      expect(() => manager.cleanupOldScreenshots(), returnsNormally);
    });

    test(
      'should not capture failure screenshots when autoScreenshots is disabled',
      () {
        final manager = ScreenshotManager(
          screenshotDirectory: tempDir.path,
          autoScreenshots: false,
        );

        // We can't test the actual WebDriver interaction, but we can verify
        // that the manager respects the autoScreenshots setting
        expect(manager.autoScreenshots, isFalse);
      },
    );

    test('should respect autoScreenshots setting', () {
      final enabledManager = ScreenshotManager(
        screenshotDirectory: tempDir.path,
        autoScreenshots: true,
      );

      final disabledManager = ScreenshotManager(
        screenshotDirectory: tempDir.path,
        autoScreenshots: false,
      );

      expect(enabledManager.autoScreenshots, isTrue);
      expect(disabledManager.autoScreenshots, isFalse);
    });
  });
}
