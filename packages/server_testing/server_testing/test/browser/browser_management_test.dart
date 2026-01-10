import 'package:server_testing/server_testing.dart';

void main() async {
  // Initialize the browser testing environment before any tests
  await testBootstrap(BrowserConfig(verbose: true, autoInstall: true));

  bool hasOverride(String browserName) =>
      TestBootstrap.getBinaryOverride(browserName) != null;

  group('Browser Management', () {
    group('listAvailableBrowsers', () {
      test('should return a list of available browsers', () async {
        final browsers = await BrowserManagement.listAvailableBrowsers();

        expect(browsers, isA<List<String>>());
        expect(browsers, isNotEmpty);

        // Should contain at least chromium and firefox
        expect(browsers, contains('chromium'));
        expect(browsers, contains('firefox'));

        print('Available browsers: $browsers');
      });

      test('should handle registry not initialized gracefully', () async {
        // This test would need to be run in isolation or with a way to reset registry
        // For now, we'll just verify it doesn't throw when registry is available
        final browsers = await BrowserManagement.listAvailableBrowsers();
        expect(browsers, isNotEmpty);
      });
    });

    group('isBrowserInstalled', () {
      test('should return false for non-existent browser', () async {
        final isInstalled = await BrowserManagement.isBrowserInstalled(
          'non-existent-browser',
        );
        expect(isInstalled, isFalse);
      });

      test('should handle empty browser name', () async {
        final isInstalled = await BrowserManagement.isBrowserInstalled('');
        expect(isInstalled, isFalse);
      });

      test('should handle whitespace-only browser name', () async {
        final isInstalled = await BrowserManagement.isBrowserInstalled('   ');
        expect(isInstalled, isFalse);
      });

      test('should check chromium installation status', () async {
        final isInstalled = await BrowserManagement.isBrowserInstalled(
          'chromium',
        );
        expect(isInstalled, isA<bool>());
        print('Chromium installed: $isInstalled');
      });

      test('should check firefox installation status', () async {
        final isInstalled = await BrowserManagement.isBrowserInstalled(
          'firefox',
        );
        expect(isInstalled, isA<bool>());
        print('Firefox installed: $isInstalled');
      });

      test('should handle browser name aliases', () async {
        // Test that 'chrome' maps to 'chromium'
        final chromeInstalled = await BrowserManagement.isBrowserInstalled(
          'chrome',
        );
        final chromiumInstalled = await BrowserManagement.isBrowserInstalled(
          'chromium',
        );

        expect(chromeInstalled, equals(chromiumInstalled));
        print(
          'Chrome/Chromium alias test: chrome=$chromeInstalled, chromium=$chromiumInstalled',
        );
      });
    });

    group('getBrowserVersions', () {
      test(
        'should return version information for installed browsers',
        () async {
          final versions = await BrowserManagement.getBrowserVersions();

          expect(versions, isA<Map<String, String>>());

          // Print version information for debugging
          print('Browser versions: $versions');

          // Each version should be a non-empty string
          for (final entry in versions.entries) {
            expect(entry.key, isNotEmpty);
            expect(entry.value, isNotEmpty);
            print('  ${entry.key}: ${entry.value}');
          }
        },
      );

      test('should only include installed browsers', () async {
        final versions = await BrowserManagement.getBrowserVersions();

        // Verify each browser in the versions map is actually installed
        for (final browserName in versions.keys) {
          final isInstalled = await BrowserManagement.isBrowserInstalled(
            browserName,
          );
          expect(
            isInstalled,
            isTrue,
            reason:
                'Browser $browserName reported in versions but not installed',
          );
        }
      });
    });

    group('installBrowser', () {
      test('should handle invalid browser name', () async {
        expect(
          () => BrowserManagement.installBrowser('invalid-browser-name'),
          throwsA(isA<BrowserException>()),
        );
      });

      test('should handle empty browser name', () async {
        expect(
          () => BrowserManagement.installBrowser(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should install chromium if not already installed', () async {
        final override = hasOverride('chromium');
        final wasInstalled = await BrowserManagement.isBrowserInstalled(
          'chromium',
        );

        if (!wasInstalled) {
          print('Installing chromium...');
          final result = await BrowserManagement.installBrowser('chromium');

          expect(result, override ? isFalse : isTrue);

          // Verify installation
          final isNowInstalled = await BrowserManagement.isBrowserInstalled(
            'chromium',
          );
          expect(isNowInstalled, isTrue);

          print('Chromium installation successful');
        } else {
          print('Chromium already installed, testing force reinstall...');

          // Test force reinstall
          final result = await BrowserManagement.installBrowser(
            'chromium',
            force: true,
          );
          expect(result, override ? isFalse : isTrue);

          print('Chromium force reinstall successful');
        }
      });

      test(
        'should return false when browser already installed and not forcing',
        () async {
          // First ensure chromium is installed
          await BrowserManagement.installBrowser('chromium');

          // Try to install again without force
          final result = await BrowserManagement.installBrowser(
            'chromium',
            force: false,
          );
          expect(result, isFalse);

          print('Correctly returned false for already installed browser');
        },
      );

      test('should handle browser name aliases correctly', () async {
        // Test installing 'chrome' which should map to 'chromium'
        final result = await BrowserManagement.installBrowser('chrome');

        // Should succeed (either install or already installed)
        expect(result, isA<bool>());

        // Both 'chrome' and 'chromium' should report as installed
        final chromeInstalled = await BrowserManagement.isBrowserInstalled(
          'chrome',
        );
        final chromiumInstalled = await BrowserManagement.isBrowserInstalled(
          'chromium',
        );

        expect(chromeInstalled, isTrue);
        expect(chromiumInstalled, isTrue);

        print('Browser alias handling successful');
      });
    });

    group('updateBrowser', () {
      test('should update an installed browser', () async {
        // Ensure chromium is installed first
        await BrowserManagement.installBrowser('chromium');

        print('Updating chromium...');
        final result = await BrowserManagement.updateBrowser('chromium');

        expect(result, hasOverride('chromium') ? isFalse : isTrue);

        // Verify browser is still installed after update
        final isInstalled = await BrowserManagement.isBrowserInstalled(
          'chromium',
        );
        expect(isInstalled, isTrue);

        print('Chromium update successful');
      });

      test('should install browser if not currently installed', () async {
        // Try to update a browser that might not be installed
        // We'll use firefox for this test
        print('Updating firefox (may install if not present)...');

        final result = await BrowserManagement.updateBrowser('firefox');
        expect(result, hasOverride('firefox') ? isFalse : isA<bool>());

        // Verify browser is installed after update
        final isInstalled = await BrowserManagement.isBrowserInstalled(
          'firefox',
        );
        expect(isInstalled, isTrue);

        print('Firefox update/install successful');
      });

      test('should handle invalid browser name', () async {
        expect(
          () => BrowserManagement.updateBrowser('invalid-browser-name'),
          throwsA(isA<BrowserException>()),
        );
      });

      test('should handle empty browser name', () async {
        expect(
          () => BrowserManagement.updateBrowser(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Integration Tests', () {
      test('should demonstrate complete browser management workflow', () async {
        const testBrowser = 'chromium';

        print('\n=== Browser Management Workflow Test ===');

        // 1. List available browsers
        print('1. Listing available browsers...');
        final available = await BrowserManagement.listAvailableBrowsers();
        print('   Available: $available');
        expect(available, contains(testBrowser));

        // 2. Check initial installation status
        print('2. Checking initial installation status...');
        final initiallyInstalled = await BrowserManagement.isBrowserInstalled(
          testBrowser,
        );
        print('   Initially installed: $initiallyInstalled');

        // 3. Install browser (or verify installation)
        print('3. Installing browser...');
        final installResult = await BrowserManagement.installBrowser(
          testBrowser,
        );
        print('   Install result: $installResult');

        // 4. Verify installation
        print('4. Verifying installation...');
        final nowInstalled = await BrowserManagement.isBrowserInstalled(
          testBrowser,
        );
        print('   Now installed: $nowInstalled');
        expect(nowInstalled, isTrue);

        // 5. Get version information
        print('5. Getting version information...');
        final versions = await BrowserManagement.getBrowserVersions();
        print('   Versions: $versions');
        expect(versions, containsPair(testBrowser, isNotEmpty));

        // 6. Update browser
        print('6. Updating browser...');
        final updateResult = await BrowserManagement.updateBrowser(testBrowser);
        print('   Update result: $updateResult');

        // 7. Verify still installed after update
        print('7. Verifying installation after update...');
        final stillInstalled = await BrowserManagement.isBrowserInstalled(
          testBrowser,
        );
        print('   Still installed: $stillInstalled');
        expect(stillInstalled, isTrue);

        print('=== Workflow test completed successfully ===\n');
      });

      test('should handle multiple browsers', () async {
        print('\n=== Multiple Browser Test ===');

        final browsersToTest = ['chromium', 'firefox'];
        final results = <String, Map<String, dynamic>>{};

        for (final browser in browsersToTest) {
          print('Testing browser: $browser');

          try {
            // Check if available
            final available = await BrowserManagement.listAvailableBrowsers();
            final isAvailable = available.contains(browser);

            if (!isAvailable) {
              print('  Browser $browser not available, skipping');
              continue;
            }

            // Install
            final installResult = await BrowserManagement.installBrowser(
              browser,
            );

            // Check installation
            final isInstalled = await BrowserManagement.isBrowserInstalled(
              browser,
            );

            results[browser] = {
              'available': isAvailable,
              'installResult': installResult,
              'isInstalled': isInstalled,
            };

            print('  Results: ${results[browser]}');
          } catch (e) {
            print('  Error testing $browser: $e');
            results[browser] = {'error': e.toString()};
          }
        }

        print('Final results: $results');

        // At least one browser should be successfully installed
        final successfulInstalls = results.values
            .where((result) => result['isInstalled'] == true)
            .length;

        expect(successfulInstalls, greaterThan(0));

        print('=== Multiple browser test completed ===\n');
      });
    });

    group('Error Handling', () {
      test('should provide helpful error messages for common issues', () async {
        // Test with invalid browser name
        try {
          await BrowserManagement.installBrowser(
            'definitely-not-a-real-browser',
          );
          fail('Should have thrown an exception');
        } catch (e) {
          expect(e, isA<BrowserException>());
          expect(e.toString(), contains('not found in registry'));
          expect(e.toString(), contains('Available browsers'));
          print('Good error message for invalid browser: $e');
        }
      });

      test('should handle network-related errors gracefully', () async {
        // This test is harder to simulate without actually causing network issues
        // For now, we'll just verify that our error handling structure is in place

        // Test that our functions don't crash on various edge cases
        expect(() => BrowserManagement.isBrowserInstalled(''), returnsNormally);
        expect(
          () => BrowserManagement.isBrowserInstalled('   '),
          returnsNormally,
        );

        print('Error handling structure verified');
      });
    });
  });
}
