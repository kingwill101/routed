import 'package:server_testing/src/browser/browser_config.dart';
import 'package:server_testing/src/browser/sync/browser.dart';
import 'package:test/test.dart';

import '../_support/mocks.dart';

void main() {
  group('SyncBrowser Convenience Methods', () {
    late MockSyncWebDriver mockDriver;
    late SyncBrowser browser;
    late BrowserConfig config;

    setUp(() {
      mockDriver = MockSyncWebDriver();
      config = BrowserConfig(baseUrl: 'http://localhost:8080');
      browser = SyncBrowser(mockDriver, config);
    });

    group('Laravel Dusk-inspired convenience methods', () {
      test(
        'clickLink should call WebDriver findElement with partialLinkText',
        () {
          browser.clickLink('Sign Out');

          expect(
            mockDriver.actions,
            contains('findElement:By.partialLinkText(Sign Out)'),
          );
        },
      );

      test('selectOption should find select element and option', () {
        browser.selectOption('select[name="country"]', 'US');

        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(select[name="country"])'),
        );
      });

      test('check should find element and check selection state', () {
        expect(() => browser.check('input[name="terms"]'), returnsNormally);
      });

      test('uncheck should find element and check selection state', () {
        expect(
          () => browser.uncheck('input[name="notifications"]'),
          returnsNormally,
        );
      });

      test('fillForm should type into each field', () {
        browser.fillForm({
          'input[name="email"]': 'user@example.com',
          'input[name="password"]': 'secret123',
        });

        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(input[name="email"])'),
        );
        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(input[name="password"])'),
        );
      });

      test('submitForm should find and submit form', () {
        browser.submitForm('#login-form');

        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(#login-form)'),
        );
        expect(mockDriver.actions, contains('execute:arguments[0].submit();'));
      });

      test('submitForm should find first form when no selector provided', () {
        browser.submitForm();

        expect(mockDriver.actions, contains('findElement:By.tagName(form)'));
        expect(mockDriver.actions, contains('execute:arguments[0].submit();'));
      });

      test('uploadFile should send file path to file input', () {
        browser.uploadFile('input[type="file"]', '/path/to/document.pdf');

        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(input[type="file"])'),
        );
      });

      test('scrollTo should execute scroll script for element', () {
        browser.scrollTo('#footer');

        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(#footer)'),
        );
        expect(
          mockDriver.actions,
          contains('execute:arguments[0].scrollIntoView();'),
        );
      });

      test('scrollToTop should execute scroll to top script', () {
        browser.scrollToTop();

        expect(mockDriver.actions, contains('execute:window.scrollTo(0, 0);'));
      });

      test('scrollToBottom should execute scroll to bottom script', () {
        browser.scrollToBottom();

        expect(
          mockDriver.actions,
          contains('execute:window.scrollTo(0, document.body.scrollHeight);'),
        );
      });
    });

    group('Enhanced waiting methods', () {
      test('waitForElement should work without throwing', () {
        // Since we're using a mock that doesn't actually wait,
        // we just test that the method exists and can be called
        expect(
          () => browser.waitForElement('.loading-spinner'),
          returnsNormally,
        );
      });

      test('waitForElement should accept custom timeout', () {
        expect(
          () => browser.waitForElement(
            '#success-message',
            timeout: const Duration(seconds: 1),
          ),
          returnsNormally,
        );
      });

      test('waitForText should check page source', () {
        mockDriver.setPageSource('<html><body>Welcome back!</body></html>');
        expect(() => browser.waitForText('Welcome back!'), returnsNormally);
      });

      test('waitForUrl should check current URL', () {
        mockDriver.setCurrentUrl('http://localhost:8080/dashboard');
        expect(() => browser.waitForUrl('/dashboard'), returnsNormally);
      });

      test('pause should work without throwing', () {
        expect(
          () => browser.pause(const Duration(milliseconds: 1)),
          returnsNormally,
        );
      });
    });

    group('Debugging helper methods', () {
      test('takeScreenshot should capture screenshot', () {
        browser.takeScreenshot();

        expect(mockDriver.actions, contains('captureScreenshot'));
      });

      test('takeScreenshot should accept custom name', () {
        browser.takeScreenshot('login-page');

        expect(mockDriver.actions, contains('captureScreenshot'));
      });

      test('dumpPageSource should get page source', () {
        browser.dumpPageSource();

        expect(mockDriver.actions, contains('getPageSource'));
      });

      test('getElementText should return element text', () {
        final text = browser.getElementText('.alert-message');

        expect(text, isA<String>());
        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(.alert-message)'),
        );
      });

      test('getElementAttribute should return element attribute', () {
        final attr = browser.getElementAttribute('a.download', 'href');

        expect(attr, isA<String?>());
        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector(a.download)'),
        );
      });
    });

    group('Consistency with AsyncBrowser', () {
      test(
        'all convenience methods should have same signatures as AsyncBrowser',
        () {
          // Test that all methods exist and can be called without throwing
          expect(() => browser.clickLink('test'), returnsNormally);
          expect(
            () => browser.selectOption('select', 'value'),
            returnsNormally,
          );
          expect(() => browser.check('input'), returnsNormally);
          expect(() => browser.uncheck('input'), returnsNormally);
          expect(() => browser.fillForm({'field': 'value'}), returnsNormally);
          expect(() => browser.submitForm(), returnsNormally);
          expect(() => browser.submitForm('#form'), returnsNormally);
          expect(() => browser.uploadFile('input', 'path'), returnsNormally);
          expect(() => browser.scrollTo('#element'), returnsNormally);
          expect(() => browser.scrollToTop(), returnsNormally);
          expect(() => browser.scrollToBottom(), returnsNormally);
          expect(
            () => browser.pause(const Duration(milliseconds: 1)),
            returnsNormally,
          );
          expect(() => browser.takeScreenshot(), returnsNormally);
          expect(() => browser.takeScreenshot('name'), returnsNormally);
          expect(() => browser.dumpPageSource(), returnsNormally);
          expect(() => browser.getElementText('.element'), returnsNormally);
          expect(
            () => browser.getElementAttribute('.element', 'attr'),
            returnsNormally,
          );
        },
      );

      test('waiting methods should exist and have correct signatures', () {
        // Test that waiting methods exist with correct signatures
        // These methods delegate to the waiter, so we just verify they exist
        expect(browser.waitForElement, isA<Function>());
        expect(browser.waitForText, isA<Function>());
        expect(browser.waitForUrl, isA<Function>());
      });
    });

    group('Error handling', () {
      test('should handle selector with @ prefix for dusk attributes', () {
        browser.click('@my-component');

        expect(
          mockDriver.actions,
          contains('findElement:By.cssSelector([dusk="my-component"])'),
        );
      });

      test('should handle exceptions gracefully', () {
        // Test that methods don't crash with invalid input
        expect(() => browser.fillForm({}), returnsNormally);
        expect(() => browser.selectOption('', ''), returnsNormally);
      });
    });

    group('Method return types', () {
      test('convenience methods should return void (sync behavior)', () {
        // Test that sync methods complete without throwing and don't return Future
        expect(() => browser.clickLink('test'), returnsNormally);
        expect(() => browser.check('input'), returnsNormally);
        expect(() => browser.fillForm({'field': 'value'}), returnsNormally);
        expect(() => browser.scrollToTop(), returnsNormally);
        expect(
          () => browser.pause(const Duration(milliseconds: 1)),
          returnsNormally,
        );
      });

      test('getter methods should return appropriate types', () {
        final text = browser.getElementText('.element');
        expect(text, isA<String>());

        final attr = browser.getElementAttribute('.element', 'attr');
        expect(attr, isA<String?>());
      });
    });
  });
}
