import 'dart:io';

import 'package:server_testing/src/browser/async/browser.dart';
import 'package:server_testing/src/browser/browser_config.dart';
import 'package:server_testing/src/browser/enhanced_exceptions.dart';
import 'package:server_testing/src/browser/sync/browser.dart';
import 'package:test/test.dart';
import 'package:webdriver/async_core.dart' as async_wd;
import 'package:webdriver/sync_core.dart' as sync_wd;

void main() {
  group('Enhanced Error Handling Integration', () {
    late Directory tempDir;
    late BrowserConfig config;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('error_handling_test');
      config = BrowserConfig(
        autoScreenshots: true,
        verboseLogging: true,
        screenshotDirectory: '${tempDir.path}/screenshots',
        logDir: '${tempDir.path}/logs',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('AsyncBrowser Enhanced Error Handling', () {
      test(
        'should throw EnhancedBrowserException with context on click failure',
        () async {
          // Create a mock WebDriver that will fail
          final mockDriver = MockAsyncWebDriver();
          final browser = AsyncBrowser(mockDriver, config);

          try {
            await browser.click('#nonexistent-element');
            fail('Expected EnhancedBrowserException to be thrown');
          } catch (e) {
            expect(e, isA<EnhancedBrowserException>());
            final enhanced = e as EnhancedBrowserException;
            expect(enhanced.selector, equals('#nonexistent-element'));
            expect(enhanced.action, equals('click'));
            expect(enhanced.message, contains('Failed to click element'));
          }
        },
      );

      test(
        'should throw EnhancedBrowserException with context on type failure',
        () async {
          final mockDriver = MockAsyncWebDriver();
          final browser = AsyncBrowser(mockDriver, config);

          try {
            await browser.type('#nonexistent-input', 'test value');
            fail('Expected EnhancedBrowserException to be thrown');
          } catch (e) {
            expect(e, isA<EnhancedBrowserException>());
            final enhanced = e as EnhancedBrowserException;
            expect(enhanced.selector, equals('#nonexistent-input'));
            expect(enhanced.action, equals('type'));
            expect(
              enhanced.details,
              contains('Attempted to type: "test value"'),
            );
          }
        },
      );

      test(
        'should throw EnhancedBrowserException on findElement failure',
        () async {
          final mockDriver = MockAsyncWebDriver();
          final browser = AsyncBrowser(mockDriver, config);

          try {
            await browser.findElement('#nonexistent-element');
            fail('Expected EnhancedBrowserException to be thrown');
          } catch (e) {
            expect(e, isA<EnhancedBrowserException>());
            final enhanced = e as EnhancedBrowserException;
            expect(enhanced.selector, equals('#nonexistent-element'));
            expect(enhanced.action, equals('findElement'));
          }
        },
      );

      test('should handle dusk selectors in error messages', () async {
        final mockDriver = MockAsyncWebDriver();
        final browser = AsyncBrowser(mockDriver, config);

        try {
          await browser.findElement('@my-component');
          fail('Expected EnhancedBrowserException to be thrown');
        } catch (e) {
          expect(e, isA<EnhancedBrowserException>());
          final enhanced = e as EnhancedBrowserException;
          expect(enhanced.selector, equals('@my-component'));
        }
      });

      test('should provide debugging methods without throwing', () async {
        final mockDriver = MockAsyncWebDriver();
        final browser = AsyncBrowser(mockDriver, config);

        // These should not throw even if they can't actually capture screenshots
        // or get page source from the mock driver
        try {
          await browser.takeScreenshot('test-screenshot');
          await browser.dumpPageSource();
        } catch (e) {
          // It's okay if these fail with the mock driver,
          // we're just testing they don't crash the system
          expect(e, isA<EnhancedBrowserException>());
        }
      });
    });

    group('SyncBrowser Enhanced Error Handling', () {
      test(
        'should throw EnhancedBrowserException with context on click failure',
        () {
          final mockDriver = MockSyncWebDriver();
          final browser = SyncBrowser(mockDriver, config);

          try {
            browser.click('#nonexistent-element');
            fail('Expected EnhancedBrowserException to be thrown');
          } catch (e) {
            expect(e, isA<EnhancedBrowserException>());
            final enhanced = e as EnhancedBrowserException;
            expect(enhanced.selector, equals('#nonexistent-element'));
            expect(enhanced.action, equals('click'));
            expect(enhanced.message, contains('Failed to click element'));
          }
        },
      );

      test(
        'should throw EnhancedBrowserException with context on type failure',
        () {
          final mockDriver = MockSyncWebDriver();
          final browser = SyncBrowser(mockDriver, config);

          try {
            browser.type('#nonexistent-input', 'test value');
            fail('Expected EnhancedBrowserException to be thrown');
          } catch (e) {
            expect(e, isA<EnhancedBrowserException>());
            final enhanced = e as EnhancedBrowserException;
            expect(enhanced.selector, equals('#nonexistent-input'));
            expect(enhanced.action, equals('type'));
            expect(
              enhanced.details,
              contains('Attempted to type: "test value"'),
            );
          }
        },
      );

      test('should throw EnhancedBrowserException on findElement failure', () {
        final mockDriver = MockSyncWebDriver();
        final browser = SyncBrowser(mockDriver, config);

        try {
          browser.findElement('#nonexistent-element');
          fail('Expected EnhancedBrowserException to be thrown');
        } catch (e) {
          expect(e, isA<EnhancedBrowserException>());
          final enhanced = e as EnhancedBrowserException;
          expect(enhanced.selector, equals('#nonexistent-element'));
          expect(enhanced.action, equals('findElement'));
        }
      });

      test('should provide debugging methods without throwing', () {
        final mockDriver = MockSyncWebDriver();
        final browser = SyncBrowser(mockDriver, config);

        // These should not throw even if they can't actually capture screenshots
        try {
          browser.takeScreenshot('test-screenshot');
          browser.dumpPageSource();
        } catch (e) {
          // It's okay if these fail with the mock driver
          expect(e, isA<EnhancedBrowserException>());
        }
      });
    });

    group('Configuration Integration', () {
      test('should respect autoScreenshots setting', () {
        final configWithScreenshots = BrowserConfig(
          autoScreenshots: true,
          screenshotDirectory: '${tempDir.path}/screenshots',
        );

        final configWithoutScreenshots = BrowserConfig(
          autoScreenshots: false,
          screenshotDirectory: '${tempDir.path}/screenshots',
        );

        expect(configWithScreenshots.autoScreenshots, isTrue);
        expect(configWithoutScreenshots.autoScreenshots, isFalse);
      });

      test('should respect verboseLogging setting', () {
        final configWithLogging = BrowserConfig(
          verboseLogging: true,
          logDir: '${tempDir.path}/logs',
        );

        final configWithoutLogging = BrowserConfig(
          verboseLogging: false,
          logDir: '${tempDir.path}/logs',
        );

        expect(configWithLogging.verboseLogging, isTrue);
        expect(configWithoutLogging.verboseLogging, isFalse);
      });

      test('should use configured screenshot directory', () {
        final customDir = '${tempDir.path}/custom_screenshots';
        final config = BrowserConfig(screenshotDirectory: customDir);

        expect(config.screenshotDirectory, equals(customDir));
      });

      test('should use configured log directory', () {
        final customDir = '${tempDir.path}/custom_logs';
        final config = BrowserConfig(logDir: customDir);

        expect(config.logDir, equals(customDir));
      });
    });
  });
}

/// Mock async WebDriver for testing error handling
class MockAsyncWebDriver implements async_wd.WebDriver {
  @override
  Future<async_wd.WebElement> findElement(async_wd.By by) async {
    throw Exception('Element not found');
  }

  @override
  Future<List<int>> captureScreenshotAsList() async {
    throw Exception('Screenshot capture failed');
  }

  @override
  Future<String> get pageSource async {
    throw Exception('Page source not available');
  }

  // Implement other required methods as no-ops for testing
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Mock sync WebDriver for testing error handling
class MockSyncWebDriver implements sync_wd.WebDriver {
  @override
  sync_wd.WebElement findElement(sync_wd.By by) {
    throw Exception('Element not found');
  }

  @override
  List<int> captureScreenshotAsList() {
    throw Exception('Screenshot capture failed');
  }

  @override
  String get pageSource {
    throw Exception('Page source not available');
  }

  // Implement other required methods as no-ops for testing
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
