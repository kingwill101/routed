import 'dart:async';

import 'package:server_testing/src/browser/interfaces/assertions.dart';
import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

/// Mock implementation of Browser for testing Laravel Dusk-inspired assertion aliases
class MockBrowserForAssertions extends BrowserAssertions with Browser {
  final List<String> _assertionCalls = [];
  String _currentUrl = '';
  String _pageTitle = '';
  String _pageSource = '';
  final Map<String, String> _elementTexts = {};
  final Map<String, Map<String, String>> _elementAttributes = {};
  final Set<String> _presentElements = {};
  final Set<String> _checkedElements = {};
  final Set<String> _enabledElements = {};

  List<String> get assertionCalls => List.unmodifiable(_assertionCalls);

  void setCurrentUrl(String url) => _currentUrl = url;

  void setPageTitle(String title) => _pageTitle = title;

  void setPageSource(String source) => _pageSource = source;

  void setElementText(String selector, String text) =>
      _elementTexts[selector] = text;

  void setElementAttribute(String selector, String attribute, String value) {
    _elementAttributes.putIfAbsent(selector, () => {})[attribute] = value;
  }

  void setElementPresent(String selector, bool present) {
    if (present) {
      _presentElements.add(selector);
    } else {
      _presentElements.remove(selector);
    }
  }

  void setElementChecked(String selector, bool checked) {
    if (checked) {
      _checkedElements.add(selector);
    } else {
      _checkedElements.remove(selector);
    }
  }

  void setElementEnabled(String selector, bool enabled) {
    if (enabled) {
      _enabledElements.add(selector);
    } else {
      _enabledElements.remove(selector);
    }
  }

  // Mock implementations of core browser methods
  @override
  FutureOr<String> getCurrentUrl() => _currentUrl;

  @override
  FutureOr<String> getTitle() => _pageTitle;

  @override
  FutureOr<String> getPageSource() => _pageSource;

  @override
  FutureOr<bool> isPresent(String selector) =>
      _presentElements.contains(selector);

  @override
  FutureOr<dynamic> findElement(String selector) =>
      MockWebElement(selector, this);

  // Mock implementations of assertion methods that track calls
  @override
  FutureOr<Browser> assertSee(String text) {
    _assertionCalls.add('assertSee:$text');
    if (!_pageSource.contains(text)) {
      throw TestFailure(
        'Expected to see "$text" but it was not found in page source',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertDontSee(String text) {
    _assertionCalls.add('assertDontSee:$text');
    if (_pageSource.contains(text)) {
      throw TestFailure(
        'Expected not to see "$text" but it was found in page source',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertTitle(String title) {
    _assertionCalls.add('assertTitle:$title');
    if (_pageTitle != title) {
      throw TestFailure('Expected title "$title" but got "$_pageTitle"');
    }
    return this;
  }

  @override
  FutureOr<Browser> assertUrlIs(String url) {
    _assertionCalls.add('assertUrlIs:$url');
    if (_currentUrl != url) {
      throw TestFailure('Expected URL "$url" but got "$_currentUrl"');
    }
    return this;
  }

  @override
  FutureOr<Browser> assertPresent(String selector) {
    _assertionCalls.add('assertPresent:$selector');
    if (!_presentElements.contains(selector)) {
      throw TestFailure(
        'Expected element "$selector" to be present but it was not found',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertNotPresent(String selector) {
    _assertionCalls.add('assertNotPresent:$selector');
    if (_presentElements.contains(selector)) {
      throw TestFailure(
        'Expected element "$selector" not to be present but it was found',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertInputValue(String selector, String value) {
    _assertionCalls.add('assertInputValue:$selector:$value');
    final actualValue = _elementAttributes[selector]?['value'];
    if (actualValue != value) {
      throw TestFailure(
        'Expected input "$selector" to have value "$value" but got "$actualValue"',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertChecked(String selector) {
    _assertionCalls.add('assertChecked:$selector');
    if (!_checkedElements.contains(selector)) {
      throw TestFailure(
        'Expected element "$selector" to be checked but it was not',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertEnabled(String selector) {
    _assertionCalls.add('assertEnabled:$selector');
    if (!_enabledElements.contains(selector)) {
      throw TestFailure(
        'Expected element "$selector" to be enabled but it was not',
      );
    }
    return this;
  }

  @override
  FutureOr<Browser> assertDisabled(String selector) {
    _assertionCalls.add('assertDisabled:$selector');
    if (_enabledElements.contains(selector)) {
      throw TestFailure(
        'Expected element "$selector" to be disabled but it was enabled',
      );
    }
    return this;
  }

  // Stub implementations for other required methods
  @override
  FutureOr<Browser> assertTitleContains(String text) {
    _assertionCalls.add('assertTitleContains:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertPathIs(String path) {
    _assertionCalls.add('assertPathIs:$path');
    return this;
  }

  @override
  FutureOr<Browser> assertPathBeginsWith(String path) {
    _assertionCalls.add('assertPathBeginsWith:$path');
    return this;
  }

  @override
  FutureOr<Browser> assertPathEndsWith(String path) {
    _assertionCalls.add('assertPathEndsWith:$path');
    return this;
  }

  @override
  FutureOr<Browser> assertQueryStringHas(String name, [String? value]) {
    _assertionCalls.add('assertQueryStringHas:$name:${value ?? 'any'}');
    return this;
  }

  @override
  FutureOr<Browser> assertQueryStringMissing(String name) {
    _assertionCalls.add('assertQueryStringMissing:$name');
    return this;
  }

  @override
  FutureOr<Browser> assertSeeIn(String selector, String text) {
    _assertionCalls.add('assertSeeIn:$selector:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertDontSeeIn(String selector, String text) {
    _assertionCalls.add('assertDontSeeIn:$selector:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertSeeAnythingIn(String selector) {
    _assertionCalls.add('assertSeeAnythingIn:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertSeeNothingIn(String selector) {
    _assertionCalls.add('assertSeeNothingIn:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertVisible(String selector) {
    _assertionCalls.add('assertVisible:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertMissing(String selector) {
    _assertionCalls.add('assertMissing:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertInputPresent(String name) {
    _assertionCalls.add('assertInputPresent:$name');
    return this;
  }

  @override
  FutureOr<Browser> assertInputMissing(String name) {
    _assertionCalls.add('assertInputMissing:$name');
    return this;
  }

  @override
  FutureOr<Browser> assertInputValueIsNot(String field, String value) {
    _assertionCalls.add('assertInputValueIsNot:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertNotChecked(String field) {
    _assertionCalls.add('assertNotChecked:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertRadioSelected(String field, String value) {
    _assertionCalls.add('assertRadioSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertRadioNotSelected(String field, String value) {
    _assertionCalls.add('assertRadioNotSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertSelected(String field, String value) {
    _assertionCalls.add('assertSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertNotSelected(String field, String value) {
    _assertionCalls.add('assertNotSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertFocused(String field) {
    _assertionCalls.add('assertFocused:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertNotFocused(String field) {
    _assertionCalls.add('assertNotFocused:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertAuthenticated([String? guard]) {
    _assertionCalls.add('assertAuthenticated:${guard ?? 'default'}');
    return this;
  }

  @override
  FutureOr<Browser> assertGuest([String? guard]) {
    _assertionCalls.add('assertGuest:${guard ?? 'default'}');
    return this;
  }

  // Stub implementations for Browser interface methods
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockWebElement {
  final String selector;
  final MockBrowserForAssertions browser;

  MockWebElement(this.selector, this.browser);

  String get text => browser._elementTexts[selector] ?? '';

  Map<String, String> get attributes =>
      browser._elementAttributes[selector] ?? {};

  bool get selected => browser._checkedElements.contains(selector);

  bool get enabled => browser._enabledElements.contains(selector);
}

void main() {
  group('Laravel Dusk-inspired Assertion Aliases', () {
    late MockBrowserForAssertions browser;

    setUp(() {
      browser = MockBrowserForAssertions();
    });

    group('shouldSee', () {
      test(
        'should delegate to assertSee and return browser instance',
        () async {
          browser.setPageSource('Welcome to our application!');

          final result = await browser.shouldSee('Welcome');

          expect(result, equals(browser));
          expect(browser.assertionCalls, contains('assertSee:Welcome'));
        },
      );

      test('should throw TestFailure when text is not found', () async {
        browser.setPageSource('Some other content');

        expect(
          () async => await browser.shouldSee('Welcome'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with special characters and spaces', () async {
        browser.setPageSource(
          'User logged in successfully! Welcome back, John.',
        );

        final result = await browser.shouldSee('Welcome back, John');

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertSee:Welcome back, John'),
        );
      });
    });

    group('shouldNotSee', () {
      test(
        'should delegate to assertDontSee and return browser instance',
        () async {
          browser.setPageSource('Welcome to our application!');

          final result = await browser.shouldNotSee('Error');

          expect(result, equals(browser));
          expect(browser.assertionCalls, contains('assertDontSee:Error'));
        },
      );

      test('should throw TestFailure when text is found', () async {
        browser.setPageSource('Error: Something went wrong');

        expect(
          () async => await browser.shouldNotSee('Error'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with text not in page', () async {
        browser.setPageSource('Some content');

        final result = await browser.shouldNotSee('Missing text');

        expect(result, equals(browser));
        expect(browser.assertionCalls, contains('assertDontSee:Missing text'));
      });
    });

    group('shouldHaveTitle', () {
      test(
        'should delegate to assertTitle and return browser instance',
        () async {
          browser.setPageTitle('Dashboard - MyApp');

          final result = await browser.shouldHaveTitle('Dashboard - MyApp');

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertTitle:Dashboard - MyApp'),
          );
        },
      );

      test('should throw TestFailure when title does not match', () async {
        browser.setPageTitle('Home - MyApp');

        expect(
          () async => await browser.shouldHaveTitle('Dashboard - MyApp'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with special characters in title', () async {
        browser.setPageTitle('Café & Restaurant - Ñoño\'s Place');

        final result = await browser.shouldHaveTitle(
          'Café & Restaurant - Ñoño\'s Place',
        );

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertTitle:Café & Restaurant - Ñoño\'s Place'),
        );
      });
    });

    group('shouldBeOn', () {
      test(
        'should delegate to assertUrlIs and return browser instance',
        () async {
          browser.setCurrentUrl('/dashboard');

          final result = await browser.shouldBeOn('/dashboard');

          expect(result, equals(browser));
          expect(browser.assertionCalls, contains('assertUrlIs:/dashboard'));
        },
      );

      test('should throw TestFailure when URL does not match', () async {
        browser.setCurrentUrl('/home');

        expect(
          () async => await browser.shouldBeOn('/dashboard'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with full URLs', () async {
        browser.setCurrentUrl('https://example.com/users/profile');

        final result = await browser.shouldBeOn(
          'https://example.com/users/profile',
        );

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertUrlIs:https://example.com/users/profile'),
        );
      });

      test('should work with query parameters', () async {
        browser.setCurrentUrl('/search?q=test&page=1');

        final result = await browser.shouldBeOn('/search?q=test&page=1');

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertUrlIs:/search?q=test&page=1'),
        );
      });
    });

    group('shouldHaveElement', () {
      test(
        'should delegate to assertPresent and return browser instance',
        () async {
          browser.setElementPresent('.success-message', true);

          final result = await browser.shouldHaveElement('.success-message');

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertPresent:.success-message'),
          );
        },
      );

      test('should throw TestFailure when element is not present', () async {
        browser.setElementPresent('.success-message', false);

        expect(
          () async => await browser.shouldHaveElement('.success-message'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with complex selectors', () async {
        browser.setElementPresent('form#login input[type="email"]', true);

        final result = await browser.shouldHaveElement(
          'form#login input[type="email"]',
        );

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertPresent:form#login input[type="email"]'),
        );
      });
    });

    group('shouldNotHaveElement', () {
      test(
        'should delegate to assertNotPresent and return browser instance',
        () async {
          browser.setElementPresent('.error-message', false);

          final result = await browser.shouldNotHaveElement('.error-message');

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertNotPresent:.error-message'),
          );
        },
      );

      test('should throw TestFailure when element is present', () async {
        browser.setElementPresent('.error-message', true);

        expect(
          () async => await browser.shouldNotHaveElement('.error-message'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with ID selectors', () async {
        browser.setElementPresent('#temporary-banner', false);

        final result = await browser.shouldNotHaveElement('#temporary-banner');

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertNotPresent:#temporary-banner'),
        );
      });
    });

    group('shouldHaveValue', () {
      test(
        'should delegate to assertInputValue and return browser instance',
        () async {
          browser.setElementAttribute(
            'input[name="email"]',
            'value',
            'user@example.com',
          );

          final result = await browser.shouldHaveValue(
            'input[name="email"]',
            'user@example.com',
          );

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertInputValue:input[name="email"]:user@example.com'),
          );
        },
      );

      test('should throw TestFailure when value does not match', () async {
        browser.setElementAttribute(
          'input[name="email"]',
          'value',
          'other@example.com',
        );

        expect(
          () async => await browser.shouldHaveValue(
            'input[name="email"]',
            'user@example.com',
          ),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with empty values', () async {
        browser.setElementAttribute('input[name="optional"]', 'value', '');

        final result = await browser.shouldHaveValue(
          'input[name="optional"]',
          '',
        );

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertInputValue:input[name="optional"]:'),
        );
      });

      test('should work with numeric values', () async {
        browser.setElementAttribute('input[name="age"]', 'value', '25');

        final result = await browser.shouldHaveValue('input[name="age"]', '25');

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertInputValue:input[name="age"]:25'),
        );
      });
    });

    group('shouldBeChecked', () {
      test(
        'should delegate to assertChecked and return browser instance',
        () async {
          browser.setElementChecked('input[name="terms"]', true);

          final result = await browser.shouldBeChecked('input[name="terms"]');

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertChecked:input[name="terms"]'),
          );
        },
      );

      test('should throw TestFailure when element is not checked', () async {
        browser.setElementChecked('input[name="terms"]', false);

        expect(
          () async => await browser.shouldBeChecked('input[name="terms"]'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with radio buttons', () async {
        browser.setElementChecked('input[name="gender"][value="male"]', true);

        final result = await browser.shouldBeChecked(
          'input[name="gender"][value="male"]',
        );

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertChecked:input[name="gender"][value="male"]'),
        );
      });
    });

    group('shouldBeEnabled', () {
      test(
        'should delegate to assertEnabled and return browser instance',
        () async {
          browser.setElementEnabled('button[type="submit"]', true);

          final result = await browser.shouldBeEnabled('button[type="submit"]');

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertEnabled:button[type="submit"]'),
          );
        },
      );

      test('should throw TestFailure when element is not enabled', () async {
        browser.setElementEnabled('button[type="submit"]', false);

        expect(
          () async => await browser.shouldBeEnabled('button[type="submit"]'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with input fields', () async {
        browser.setElementEnabled('input[name="username"]', true);

        final result = await browser.shouldBeEnabled('input[name="username"]');

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertEnabled:input[name="username"]'),
        );
      });
    });

    group('shouldBeDisabled', () {
      test(
        'should delegate to assertDisabled and return browser instance',
        () async {
          browser.setElementEnabled('input[name="readonly"]', false);

          final result = await browser.shouldBeDisabled(
            'input[name="readonly"]',
          );

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertDisabled:input[name="readonly"]'),
          );
        },
      );

      test('should throw TestFailure when element is enabled', () async {
        browser.setElementEnabled('input[name="readonly"]', true);

        expect(
          () async => await browser.shouldBeDisabled('input[name="readonly"]'),
          throwsA(isA<TestFailure>()),
        );
      });

      test('should work with select elements', () async {
        browser.setElementEnabled('select[name="country"]', false);

        final result = await browser.shouldBeDisabled('select[name="country"]');

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertDisabled:select[name="country"]'),
        );
      });
    });

    group('Method Chaining', () {
      test(
        'should allow chaining multiple Laravel Dusk-style assertions',
        () async {
          // Set up the browser state
          browser.setPageTitle('Dashboard - MyApp');
          browser.setCurrentUrl('/dashboard');
          browser.setPageSource('Welcome back, John! Your dashboard is ready.');
          browser.setElementPresent('.user-info', true);
          browser.setElementAttribute(
            'input[name="email"]',
            'value',
            'john@example.com',
          );
          browser.setElementChecked('input[name="notifications"]', true);
          browser.setElementEnabled('button[type="submit"]', true);

          // Chain multiple assertions by awaiting each one
          var result = await browser.shouldHaveTitle('Dashboard - MyApp');
          result = await result.shouldBeOn('/dashboard');
          result = await result.shouldSee('Welcome back, John');
          result = await result.shouldHaveElement('.user-info');
          result = await result.shouldHaveValue(
            'input[name="email"]',
            'john@example.com',
          );
          result = await result.shouldBeChecked('input[name="notifications"]');
          result = await result.shouldBeEnabled('button[type="submit"]');

          expect(result, equals(browser));

          // Verify all assertions were called
          expect(
            browser.assertionCalls,
            contains('assertTitle:Dashboard - MyApp'),
          );
          expect(browser.assertionCalls, contains('assertUrlIs:/dashboard'));
          expect(
            browser.assertionCalls,
            contains('assertSee:Welcome back, John'),
          );
          expect(browser.assertionCalls, contains('assertPresent:.user-info'));
          expect(
            browser.assertionCalls,
            contains('assertInputValue:input[name="email"]:john@example.com'),
          );
          expect(
            browser.assertionCalls,
            contains('assertChecked:input[name="notifications"]'),
          );
          expect(
            browser.assertionCalls,
            contains('assertEnabled:button[type="submit"]'),
          );
        },
      );

      test(
        'should allow mixing Laravel Dusk-style with traditional assertions',
        () async {
          browser.setPageTitle('Mixed Test Page');
          browser.setPageSource('Content with mixed assertions');
          browser.setElementPresent('#main-content', true);

          var result = await browser.shouldHaveTitle('Mixed Test Page');
          result = await result.assertSee('mixed assertions');
          result = await result.shouldHaveElement('#main-content');

          expect(result, equals(browser));
          expect(
            browser.assertionCalls,
            contains('assertTitle:Mixed Test Page'),
          );
          expect(
            browser.assertionCalls,
            contains('assertSee:mixed assertions'),
          );
          expect(
            browser.assertionCalls,
            contains('assertPresent:#main-content'),
          );
        },
      );
    });

    group('Edge Cases', () {
      test('should handle null and empty string inputs gracefully', () async {
        browser.setPageSource('');
        browser.setPageTitle('');
        browser.setCurrentUrl('');

        final result1 = await browser.shouldHaveTitle('');
        final result2 = await browser.shouldBeOn('');
        final result3 = await browser.shouldNotSee('anything');

        expect(result1, equals(browser));
        expect(result2, equals(browser));
        expect(result3, equals(browser));
      });

      test('should handle special CSS selectors', () async {
        const complexSelector =
            'div.container > ul:nth-child(2) li[data-id="123"]:not(.hidden)';
        browser.setElementPresent(complexSelector, true);

        final result = await browser.shouldHaveElement(complexSelector);

        expect(result, equals(browser));
        expect(
          browser.assertionCalls,
          contains('assertPresent:$complexSelector'),
        );
      });

      test('should handle Unicode characters in text assertions', () async {
        const unicodeText = 'Café ñoño 中文 🎉 emoji test';
        browser.setPageSource('Welcome to our $unicodeText page!');

        final result = await browser.shouldSee(unicodeText);

        expect(result, equals(browser));
        expect(browser.assertionCalls, contains('assertSee:$unicodeText'));
      });
    });
  });
}
