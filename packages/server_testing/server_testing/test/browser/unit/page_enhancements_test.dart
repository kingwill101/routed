import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:server_testing/src/browser/page.dart';
import 'package:test/test.dart';

/// Mock browser implementation for testing Page enhancements
class MockBrowser implements Browser {
  final List<String> _actions = [];
  final Map<String, dynamic> _state = {};

  List<String> get actions => List.unmodifiable(_actions);

  Map<String, dynamic> get state => _state;

  void reset() {
    _actions.clear();
    _state.clear();
  }

  @override
  Future<void> visit(String url) async {
    _actions.add('visit:$url');
    _state['currentUrl'] = url;
  }

  @override
  Future<void> type(String selector, String value) async {
    _actions.add('type:$selector:$value');
  }

  @override
  Future<void> click(String selector) async {
    _actions.add('click:$selector');
  }

  @override
  Future<void> waitForElement(String selector, {Duration? timeout}) async {
    _actions.add(
      'waitForElement:$selector${timeout != null ? ':${timeout.inMilliseconds}ms' : ''}',
    );
  }

  @override
  Future<Browser> assertUrlIs(String expectedUrl) async {
    _actions.add('assertUrlIs:$expectedUrl');
    if (_state['currentUrl'] != expectedUrl) {
      throw Exception(
        'Expected URL $expectedUrl but was ${_state['currentUrl']}',
      );
    }
    return this;
  }

  // Implement specific methods we need for testing
  @override
  Future<void> waitForText(String text, {Duration? timeout}) async {
    _actions.add('waitForText:$text');
  }

  @override
  Future<void> takeScreenshot([String? name]) async {
    _actions.add('takeScreenshot:${name ?? 'auto'}');
  }

  // Only implement the methods we need for testing Page enhancements
  @override
  noSuchMethod(Invocation invocation) {
    // For any unimplemented methods, just return a mock value
    final methodName = invocation.memberName
        .toString()
        .replaceAll('Symbol("', '')
        .replaceAll('")', '');
    _actions.add('$methodName:called');

    // Return appropriate mock values based on return type expectations
    if (methodName.startsWith('assert') || methodName.startsWith('should')) {
      return Future<dynamic>.value(this);
    }
    return Future<void>.value();
  }
}

/// Test page implementation for testing Page enhancements
class TestPage extends Page {
  TestPage(super.browser);

  @override
  String get url => '/test-page';

  // Test-specific page elements
  String get emailField => '#email';

  String get passwordField => '#password';

  String get submitButton => '#submit-btn';

  String get cancelButton => '.cancel-btn';

  // Test-specific page methods using enhanced functionality
  Future<void> enterCredentials(String email, String password) async {
    await fillField(emailField, email);
    await fillField(passwordField, password);
  }

  Future<void> submitForm() async {
    await clickButton(submitButton);
  }

  Future<void> cancelForm() async {
    await clickButton(cancelButton);
  }
}

void main() {
  group('Page Enhancements', () {
    late MockBrowser mockBrowser;
    late TestPage testPage;

    setUp(() {
      mockBrowser = MockBrowser();
      testPage = TestPage(mockBrowser);
    });

    group('waitForLoad method', () {
      test('waits for body element with default timeout', () async {
        await testPage.waitForLoad();

        expect(mockBrowser.actions, contains('waitForElement:body'));
      });

      test('waits for body element with custom timeout', () async {
        const customTimeout = Duration(seconds: 5);
        await testPage.waitForLoad(timeout: customTimeout);

        expect(mockBrowser.actions, contains('waitForElement:body:5000ms'));
      });

      test('integrates with page navigation workflow', () async {
        await testPage.navigate();
        await testPage.waitForLoad();

        expect(mockBrowser.actions, [
          'visit:/test-page',
          'waitForElement:body',
        ]);
      });

      test('can be used after assertOnPage', () async {
        mockBrowser.state['currentUrl'] = '/test-page';

        await testPage.navigate();
        await testPage.waitForLoad();
        await testPage.assertOnPage();

        expect(mockBrowser.actions, [
          'visit:/test-page',
          'waitForElement:body',
          'assertUrlIs:/test-page',
        ]);
      });
    });

    group('fillField method', () {
      test('fills a form field with specified value', () async {
        await testPage.fillField('#username', 'testuser');

        expect(mockBrowser.actions, contains('type:#username:testuser'));
      });

      test('can be used multiple times for different fields', () async {
        await testPage.fillField('#email', 'user@example.com');
        await testPage.fillField('#password', 'secret123');

        expect(mockBrowser.actions, [
          'type:#email:user@example.com',
          'type:#password:secret123',
        ]);
      });

      test('integrates with page-specific methods', () async {
        await testPage.enterCredentials('user@example.com', 'password123');

        expect(mockBrowser.actions, [
          'type:#email:user@example.com',
          'type:#password:password123',
        ]);
      });

      test('works with complex selectors', () async {
        await testPage.fillField(
          'form.login input[name="email"]',
          'test@example.com',
        );

        expect(
          mockBrowser.actions,
          contains('type:form.login input[name="email"]:test@example.com'),
        );
      });

      test('handles empty values', () async {
        await testPage.fillField('#search', '');

        expect(mockBrowser.actions, contains('type:#search:'));
      });

      test('handles special characters in values', () async {
        await testPage.fillField('#message', 'Hello "world" & <test>');

        expect(
          mockBrowser.actions,
          contains('type:#message:Hello "world" & <test>'),
        );
      });
    });

    group('clickButton method', () {
      test('clicks a button element', () async {
        await testPage.clickButton('#submit');

        expect(mockBrowser.actions, contains('click:#submit'));
      });

      test('can be used multiple times for different buttons', () async {
        await testPage.clickButton('#save');
        await testPage.clickButton('#cancel');

        expect(mockBrowser.actions, ['click:#save', 'click:#cancel']);
      });

      test('integrates with page-specific methods', () async {
        await testPage.submitForm();
        await testPage.cancelForm();

        expect(mockBrowser.actions, ['click:#submit-btn', 'click:.cancel-btn']);
      });

      test('works with complex selectors', () async {
        await testPage.clickButton('form.registration button[type="submit"]');

        expect(
          mockBrowser.actions,
          contains('click:form.registration button[type="submit"]'),
        );
      });

      test('works with class-based selectors', () async {
        await testPage.clickButton('.btn-primary');

        expect(mockBrowser.actions, contains('click:.btn-primary'));
      });
    });

    group('Enhanced Page workflow integration', () {
      test('complete page interaction workflow', () async {
        // Navigate to page
        await testPage.navigate();

        // Wait for page to load
        await testPage.waitForLoad();

        // Fill form fields
        await testPage.enterCredentials('user@example.com', 'password123');

        // Submit form
        await testPage.submitForm();

        // Verify actions were called in correct order
        expect(mockBrowser.actions, [
          'visit:/test-page',
          'waitForElement:body',
          'type:#email:user@example.com',
          'type:#password:password123',
          'click:#submit-btn',
        ]);
      });

      test('page methods work seamlessly with browser interface', () async {
        // Mix page methods with direct browser calls
        await testPage.navigate();
        await testPage.waitForLoad();
        await mockBrowser.waitForText('Welcome');
        await testPage.fillField('#search', 'test query');
        await mockBrowser.takeScreenshot('search-filled');
        await testPage.clickButton('#search-btn');

        expect(mockBrowser.actions, [
          'visit:/test-page',
          'waitForElement:body',
          'waitForText:Welcome',
          'type:#search:test query',
          'takeScreenshot:search-filled',
          'click:#search-btn',
        ]);
      });

      test('enhanced methods support async/await patterns', () async {
        // Test that all methods properly support async/await
        await testPage.fillField('#field1', 'value1');
        await testPage.fillField('#field2', 'value2');

        await testPage.clickButton('#submit');

        // Both fill operations should complete before click
        expect(mockBrowser.actions, [
          'type:#field1:value1',
          'type:#field2:value2',
          'click:#submit',
        ]);
      });

      test('page methods maintain backward compatibility', () async {
        // Test that existing Page functionality still works
        await testPage.navigate();
        mockBrowser.state['currentUrl'] = '/test-page';
        await testPage.assertOnPage();

        expect(mockBrowser.actions, [
          'visit:/test-page',
          'assertUrlIs:/test-page',
        ]);
      });
    });

    group('Error handling and edge cases', () {
      test('methods handle null and empty selectors gracefully', () async {
        // These should not throw, but delegate to browser implementation
        await testPage.fillField('', 'value');
        await testPage.clickButton('');

        expect(mockBrowser.actions, ['type::value', 'click:']);
      });

      test('waitForLoad with zero timeout', () async {
        await testPage.waitForLoad(timeout: Duration.zero);

        expect(mockBrowser.actions, contains('waitForElement:body:0ms'));
      });

      test('fillField with very long values', () async {
        final longValue = 'a' * 1000;
        await testPage.fillField('#textarea', longValue);

        expect(mockBrowser.actions, contains('type:#textarea:$longValue'));
      });
    });
  });
}
