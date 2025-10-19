import 'package:server_testing/src/browser/browser_config.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserConfig', () {
    group('default values', () {
      test('should have correct default values for new properties', () {
        final config = BrowserConfig();

        expect(config.autoScreenshots, isFalse);
        expect(config.defaultWaitTimeout, equals(const Duration(seconds: 10)));
        expect(config.verboseLogging, isFalse);
        expect(config.screenshotDirectory, equals('test_screenshots'));
        expect(config.autoInstall, isTrue);
      });

      test('should maintain backward compatibility with existing defaults', () {
        final config = BrowserConfig();

        expect(config.browserName, equals('chromium'));
        expect(config.headless, isTrue);
        expect(config.timeout, equals(const Duration(seconds: 30)));
        expect(config.screenshotPath, equals('test/screenshots'));
        expect(config.baseUrl, equals('http://localhost:8000'));
        expect(config.autoDownload, isTrue);
        expect(config.verbose, isFalse);
        expect(config.debug, isFalse);
        expect(config.enableCache, isTrue);
        expect(config.forceReinstall, isFalse);
        expect(config.logDir, equals('test/logs'));
      });
    });

    group('constructor parameters', () {
      test('should accept autoScreenshots parameter', () {
        final config = BrowserConfig(autoScreenshots: true);
        expect(config.autoScreenshots, isTrue);
      });

      test('should accept defaultWaitTimeout parameter', () {
        final timeout = const Duration(seconds: 20);
        final config = BrowserConfig(defaultWaitTimeout: timeout);
        expect(config.defaultWaitTimeout, equals(timeout));
      });

      test('should accept verboseLogging parameter', () {
        final config = BrowserConfig(verboseLogging: true);
        expect(config.verboseLogging, isTrue);
      });

      test('should accept screenshotDirectory parameter', () {
        final config = BrowserConfig(screenshotDirectory: 'custom/screenshots');
        expect(config.screenshotDirectory, equals('custom/screenshots'));
      });

      test('should accept autoInstall parameter', () {
        final config = BrowserConfig(autoInstall: false);
        expect(config.autoInstall, isFalse);
      });

      test('should accept all new parameters together', () {
        final config = BrowserConfig(
          autoScreenshots: true,
          defaultWaitTimeout: const Duration(seconds: 15),
          verboseLogging: true,
          screenshotDirectory: 'custom/path',
          autoInstall: false,
        );

        expect(config.autoScreenshots, isTrue);
        expect(config.defaultWaitTimeout, equals(const Duration(seconds: 15)));
        expect(config.verboseLogging, isTrue);
        expect(config.screenshotDirectory, equals('custom/path'));
        expect(config.autoInstall, isFalse);
      });
    });

    group('copyWith method', () {
      late BrowserConfig originalConfig;

      setUp(() {
        originalConfig = BrowserConfig(
          browserName: 'firefox',
          headless: false,
          autoScreenshots: true,
          defaultWaitTimeout: const Duration(seconds: 15),
          verboseLogging: true,
          screenshotDirectory: 'original/path',
          autoInstall: false,
        );
      });

      test('should copy autoScreenshots', () {
        final newConfig = originalConfig.copyWith(autoScreenshots: false);
        expect(newConfig.autoScreenshots, isFalse);
        expect(
          newConfig.browserName,
          equals('firefox'),
        ); // Other values preserved
      });

      test('should copy defaultWaitTimeout', () {
        final newTimeout = const Duration(seconds: 25);
        final newConfig = originalConfig.copyWith(
          defaultWaitTimeout: newTimeout,
        );
        expect(newConfig.defaultWaitTimeout, equals(newTimeout));
        expect(newConfig.verboseLogging, isTrue); // Other values preserved
      });

      test('should copy verboseLogging', () {
        final newConfig = originalConfig.copyWith(verboseLogging: false);
        expect(newConfig.verboseLogging, isFalse);
        expect(newConfig.autoScreenshots, isTrue); // Other values preserved
      });

      test('should copy screenshotDirectory', () {
        final newConfig = originalConfig.copyWith(
          screenshotDirectory: 'new/path',
        );
        expect(newConfig.screenshotDirectory, equals('new/path'));
        expect(newConfig.autoInstall, isFalse); // Other values preserved
      });

      test('should copy autoInstall', () {
        final newConfig = originalConfig.copyWith(autoInstall: true);
        expect(newConfig.autoInstall, isTrue);
        expect(newConfig.headless, isFalse); // Other values preserved
      });

      test('should copy multiple new properties at once', () {
        final newConfig = originalConfig.copyWith(
          autoScreenshots: false,
          defaultWaitTimeout: const Duration(seconds: 30),
          verboseLogging: false,
          screenshotDirectory: 'multi/path',
          autoInstall: true,
        );

        expect(newConfig.autoScreenshots, isFalse);
        expect(
          newConfig.defaultWaitTimeout,
          equals(const Duration(seconds: 30)),
        );
        expect(newConfig.verboseLogging, isFalse);
        expect(newConfig.screenshotDirectory, equals('multi/path'));
        expect(newConfig.autoInstall, isTrue);

        // Verify original values are preserved for unchanged properties
        expect(newConfig.browserName, equals('firefox'));
        expect(newConfig.headless, isFalse);
      });

      test('should preserve original values when no parameters provided', () {
        final newConfig = originalConfig.copyWith();

        expect(
          newConfig.autoScreenshots,
          equals(originalConfig.autoScreenshots),
        );
        expect(
          newConfig.defaultWaitTimeout,
          equals(originalConfig.defaultWaitTimeout),
        );
        expect(newConfig.verboseLogging, equals(originalConfig.verboseLogging));
        expect(
          newConfig.screenshotDirectory,
          equals(originalConfig.screenshotDirectory),
        );
        expect(newConfig.autoInstall, equals(originalConfig.autoInstall));
        expect(newConfig.browserName, equals(originalConfig.browserName));
        expect(newConfig.headless, equals(originalConfig.headless));
      });
    });

    group('backward compatibility', () {
      test(
        'should work with existing code that does not use new properties',
        () {
          // This simulates existing code that only uses original properties
          final config = BrowserConfig(
            browserName: 'chrome',
            headless: true,
            timeout: const Duration(seconds: 45),
            baseUrl: 'http://localhost:3000',
          );

          // Original properties should work as before
          expect(config.browserName, equals('chrome'));
          expect(config.headless, isTrue);
          expect(config.timeout, equals(const Duration(seconds: 45)));
          expect(config.baseUrl, equals('http://localhost:3000'));

          // New properties should have their default values
          expect(config.autoScreenshots, isFalse);
          expect(
            config.defaultWaitTimeout,
            equals(const Duration(seconds: 10)),
          );
          expect(config.verboseLogging, isFalse);
          expect(config.screenshotDirectory, equals('test_screenshots'));
          expect(config.autoInstall, isTrue);
        },
      );

      test('should work with existing copyWith calls', () {
        final originalConfig = BrowserConfig();

        // This simulates existing code that uses copyWith with original properties only
        final newConfig = originalConfig.copyWith(
          browserName: 'firefox',
          headless: false,
          timeout: const Duration(seconds: 60),
        );

        // Original properties should be updated
        expect(newConfig.browserName, equals('firefox'));
        expect(newConfig.headless, isFalse);
        expect(newConfig.timeout, equals(const Duration(seconds: 60)));

        // New properties should retain their default values
        expect(newConfig.autoScreenshots, isFalse);
        expect(
          newConfig.defaultWaitTimeout,
          equals(const Duration(seconds: 10)),
        );
        expect(newConfig.verboseLogging, isFalse);
        expect(newConfig.screenshotDirectory, equals('test_screenshots'));
        expect(newConfig.autoInstall, isTrue);
      });
    });

    group('Laravel Dusk-inspired configuration', () {
      test('should support Laravel Dusk-like configuration patterns', () {
        final config = BrowserConfig(
          browserName: 'chromium',
          headless: false,
          autoScreenshots: true,
          defaultWaitTimeout: const Duration(seconds: 15),
          verboseLogging: true,
          screenshotDirectory: 'tests/screenshots',
          autoInstall: true,
        );

        expect(config.browserName, equals('chromium'));
        expect(config.headless, isFalse);
        expect(config.autoScreenshots, isTrue);
        expect(config.defaultWaitTimeout, equals(const Duration(seconds: 15)));
        expect(config.verboseLogging, isTrue);
        expect(config.screenshotDirectory, equals('tests/screenshots'));
        expect(config.autoInstall, isTrue);
      });

      test('should differentiate between autoDownload and autoInstall', () {
        // Both should be available for different use cases
        final config1 = BrowserConfig(autoDownload: false, autoInstall: true);

        final config2 = BrowserConfig(autoDownload: true, autoInstall: false);

        expect(config1.autoDownload, isFalse);
        expect(config1.autoInstall, isTrue);
        expect(config2.autoDownload, isTrue);
        expect(config2.autoInstall, isFalse);
      });

      test(
        'should differentiate between screenshotPath and screenshotDirectory',
        () {
          // Both should be available for different use cases
          final config = BrowserConfig(
            screenshotPath: 'test/screenshots',
            screenshotDirectory: 'test_screenshots',
          );

          expect(config.screenshotPath, equals('test/screenshots'));
          expect(config.screenshotDirectory, equals('test_screenshots'));
        },
      );

      test('should differentiate between verbose and verboseLogging', () {
        // Both should be available for different levels of logging
        final config = BrowserConfig(verbose: true, verboseLogging: false);

        expect(config.verbose, isTrue);
        expect(config.verboseLogging, isFalse);
      });
    });

    group('sensible defaults validation', () {
      test('should have sensible default timeout values', () {
        final config = BrowserConfig();

        // General timeout should be longer than wait timeout for most operations
        expect(
          config.timeout.inSeconds,
          greaterThan(config.defaultWaitTimeout.inSeconds),
        );

        // Wait timeout should be reasonable for UI interactions
        expect(config.defaultWaitTimeout.inSeconds, greaterThanOrEqualTo(5));
        expect(config.defaultWaitTimeout.inSeconds, lessThanOrEqualTo(30));
      });

      test('should have sensible default directory paths', () {
        final config = BrowserConfig();

        // Screenshot directories should be different to avoid conflicts
        expect(
          config.screenshotPath,
          isNot(equals(config.screenshotDirectory)),
        );

        // Paths should be reasonable
        expect(config.screenshotDirectory, isNotEmpty);
        expect(config.logDir, isNotEmpty);
      });

      test('should have conservative defaults for new features', () {
        final config = BrowserConfig();

        // New features should be opt-in by default (except autoInstall which improves UX)
        expect(
          config.autoScreenshots,
          isFalse,
          reason: 'Screenshots should be opt-in',
        );
        expect(
          config.verboseLogging,
          isFalse,
          reason: 'Verbose logging should be opt-in',
        );
        expect(
          config.autoInstall,
          isTrue,
          reason: 'Auto-install improves developer experience',
        );
      });
    });
  });
}
