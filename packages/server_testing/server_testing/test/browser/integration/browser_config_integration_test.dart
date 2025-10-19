import 'package:server_testing/src/browser/browser_config.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserConfig Integration', () {
    test(
      'should work with testBootstrap using new configuration options',
      () async {
        // Create a config with new Laravel Dusk-inspired options
        final config = BrowserConfig(
          browserName: 'chromium',
          headless: true,
          autoScreenshots: true,
          defaultWaitTimeout: const Duration(seconds: 15),
          verboseLogging: false,
          // Keep false to avoid noise in tests
          screenshotDirectory: 'test_integration_screenshots',
          autoInstall: true,
        );

        // Verify the configuration is properly set
        expect(config.autoScreenshots, isTrue);
        expect(config.defaultWaitTimeout, equals(const Duration(seconds: 15)));
        expect(config.verboseLogging, isFalse);
        expect(
          config.screenshotDirectory,
          equals('test_integration_screenshots'),
        );
        expect(config.autoInstall, isTrue);

        // Verify backward compatibility - existing properties should still work
        expect(config.browserName, equals('chromium'));
        expect(config.headless, isTrue);
        expect(
          config.timeout,
          equals(const Duration(seconds: 30)),
        ); // Default value
        expect(
          config.baseUrl,
          equals('http://localhost:8000'),
        ); // Default value
      },
    );

    test(
      'should create different configurations for different test scenarios',
      () {
        // Development configuration - visible browser with debugging features
        final devConfig = BrowserConfig(
          browserName: 'chromium',
          headless: false,
          autoScreenshots: true,
          defaultWaitTimeout: const Duration(seconds: 20),
          verboseLogging: true,
          screenshotDirectory: 'dev_screenshots',
          autoInstall: true,
        );

        // CI configuration - headless with minimal logging
        final ciConfig = BrowserConfig(
          browserName: 'chromium',
          headless: true,
          autoScreenshots: false,
          defaultWaitTimeout: const Duration(seconds: 10),
          verboseLogging: false,
          screenshotDirectory: 'ci_screenshots',
          autoInstall: true,
        );

        // Verify configurations are different
        expect(devConfig.headless, isFalse);
        expect(ciConfig.headless, isTrue);

        expect(devConfig.autoScreenshots, isTrue);
        expect(ciConfig.autoScreenshots, isFalse);

        expect(devConfig.verboseLogging, isTrue);
        expect(ciConfig.verboseLogging, isFalse);

        expect(devConfig.screenshotDirectory, equals('dev_screenshots'));
        expect(ciConfig.screenshotDirectory, equals('ci_screenshots'));
      },
    );

    test('should support copyWith for configuration overrides', () {
      // Base configuration
      final baseConfig = BrowserConfig(
        browserName: 'firefox',
        headless: true,
        autoScreenshots: false,
        defaultWaitTimeout: const Duration(seconds: 10),
        verboseLogging: false,
        screenshotDirectory: 'base_screenshots',
        autoInstall: true,
      );

      // Override for debugging
      final debugConfig = baseConfig.copyWith(
        headless: false,
        autoScreenshots: true,
        verboseLogging: true,
        screenshotDirectory: 'debug_screenshots',
      );

      // Verify base config is unchanged
      expect(baseConfig.headless, isTrue);
      expect(baseConfig.autoScreenshots, isFalse);
      expect(baseConfig.verboseLogging, isFalse);
      expect(baseConfig.screenshotDirectory, equals('base_screenshots'));

      // Verify debug config has overrides
      expect(debugConfig.headless, isFalse);
      expect(debugConfig.autoScreenshots, isTrue);
      expect(debugConfig.verboseLogging, isTrue);
      expect(debugConfig.screenshotDirectory, equals('debug_screenshots'));

      // Verify unchanged properties are preserved
      expect(debugConfig.browserName, equals('firefox'));
      expect(
        debugConfig.defaultWaitTimeout,
        equals(const Duration(seconds: 10)),
      );
      expect(debugConfig.autoInstall, isTrue);
    });

    test(
      'should maintain backward compatibility with existing usage patterns',
      () {
        // Simulate existing code that doesn't use new properties
        final legacyConfig = BrowserConfig(
          browserName: 'chrome',
          headless: true,
          timeout: const Duration(seconds: 45),
          baseUrl: 'http://localhost:3000',
          verbose: true,
        );

        // Legacy properties should work
        expect(legacyConfig.browserName, equals('chrome'));
        expect(legacyConfig.headless, isTrue);
        expect(legacyConfig.timeout, equals(const Duration(seconds: 45)));
        expect(legacyConfig.baseUrl, equals('http://localhost:3000'));
        expect(legacyConfig.verbose, isTrue);

        // New properties should have sensible defaults
        expect(legacyConfig.autoScreenshots, isFalse);
        expect(
          legacyConfig.defaultWaitTimeout,
          equals(const Duration(seconds: 10)),
        );
        expect(legacyConfig.verboseLogging, isFalse);
        expect(legacyConfig.screenshotDirectory, equals('test_screenshots'));
        expect(legacyConfig.autoInstall, isTrue);

        // Legacy copyWith should still work
        final modifiedConfig = legacyConfig.copyWith(
          browserName: 'firefox',
          headless: false,
        );

        expect(modifiedConfig.browserName, equals('firefox'));
        expect(modifiedConfig.headless, isFalse);
        expect(
          modifiedConfig.timeout,
          equals(const Duration(seconds: 45)),
        ); // Preserved
        expect(modifiedConfig.autoScreenshots, isFalse); // Default preserved
      },
    );

    test('should support Laravel Dusk-like configuration patterns', () {
      // Configuration similar to Laravel Dusk's approach
      final duskLikeConfig = BrowserConfig(
        // Browser setup
        browserName: 'chromium',
        headless: false,
        // Show browser for development

        // Enhanced debugging
        autoScreenshots: true,
        verboseLogging: true,
        screenshotDirectory: 'tests/Browser/screenshots',

        // Timeouts
        defaultWaitTimeout: const Duration(seconds: 15),
        timeout: const Duration(seconds: 60),

        // Auto-installation for convenience
        autoInstall: true,

        // Base URL for the application
        baseUrl: 'http://localhost:8000',
      );

      // Verify Laravel Dusk-like configuration
      expect(duskLikeConfig.browserName, equals('chromium'));
      expect(duskLikeConfig.headless, isFalse);
      expect(duskLikeConfig.autoScreenshots, isTrue);
      expect(duskLikeConfig.verboseLogging, isTrue);
      expect(
        duskLikeConfig.screenshotDirectory,
        equals('tests/Browser/screenshots'),
      );
      expect(
        duskLikeConfig.defaultWaitTimeout,
        equals(const Duration(seconds: 15)),
      );
      expect(duskLikeConfig.timeout, equals(const Duration(seconds: 60)));
      expect(duskLikeConfig.autoInstall, isTrue);
      expect(duskLikeConfig.baseUrl, equals('http://localhost:8000'));
    });
  });
}
