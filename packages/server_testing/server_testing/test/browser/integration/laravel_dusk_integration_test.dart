import 'package:server_testing/src/browser/interfaces/assertions.dart';
import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

/// Integration test demonstrating Laravel Dusk-inspired assertion aliases
/// in a realistic browser testing scenario.
void main() {
  group('Laravel Dusk-inspired Assertions Integration', () {
    test('should demonstrate fluent assertion API usage', () async {
      // This test demonstrates how the Laravel Dusk-inspired assertion aliases
      // would be used in a real browser testing scenario.

      // Create a mock browser that simulates a real page state
      final browser = MockIntegrationBrowser();

      // Simulate visiting a login page
      browser.simulateLoginPage();

      // Use Laravel Dusk-inspired assertions to verify page state
      var result = await browser.shouldHaveTitle('Login - MyApp');
      result = await result.shouldBeOn('/login');
      result = await result.shouldSee('Welcome back!');
      result = await result.shouldHaveElement('#login-form');
      result = await result.shouldHaveElement('input[name="email"]');
      result = await result.shouldHaveElement('input[name="password"]');
      result = await result.shouldHaveElement('button[type="submit"]');
      result = await result.shouldNotSee('Error: Invalid credentials');
      result = await result.shouldNotHaveElement('.error-message');
      result = await result.shouldBeEnabled('button[type="submit"]');

      // Simulate filling out the form
      browser.simulateFormFilled();

      // Verify form state
      result = await browser.shouldHaveValue(
        'input[name="email"]',
        'user@example.com',
      );
      result = await result.shouldHaveValue(
        'input[name="password"]',
        'password123',
      );
      result = await result.shouldBeChecked('input[name="remember"]');

      // Simulate successful login
      browser.simulateSuccessfulLogin();

      // Verify redirect and success state
      result = await browser.shouldBeOn('/dashboard');
      result = await result.shouldHaveTitle('Dashboard - MyApp');
      result = await result.shouldSee('Welcome, John Doe!');
      result = await result.shouldHaveElement('.user-profile');
      result = await result.shouldNotSee('Login');
      result = await result.shouldNotHaveElement('#login-form');

      expect(browser.assertionCount, greaterThan(15));
    });

    test(
      'should handle error scenarios with Laravel Dusk-style assertions',
      () async {
        final browser = MockIntegrationBrowser();

        // Simulate a page with errors
        browser.simulateErrorPage();

        // Use Laravel Dusk-inspired assertions to verify error state
        var result = await browser.shouldHaveTitle('Error - MyApp');
        result = await result.shouldSee('Something went wrong');
        result = await result.shouldHaveElement('.error-message');
        result = await result.shouldNotSee('Success');
        result = await result.shouldNotHaveElement('.success-message');
        result = await result.shouldBeDisabled('button[type="retry"]');

        expect(browser.assertionCount, equals(6));
      },
    );

    test('should work with form validation scenarios', () async {
      final browser = MockIntegrationBrowser();

      // Simulate a form with validation errors
      browser.simulateFormValidationErrors();

      // Verify validation state using Laravel Dusk-style assertions
      var result = await browser.shouldSee(
        'Please correct the following errors:',
      );
      result = await result.shouldHaveElement('.validation-error');
      result = await result.shouldSee('Email is required');
      result = await result.shouldSee('Password must be at least 8 characters');
      result = await result.shouldHaveValue('input[name="email"]', '');
      result = await result.shouldHaveValue('input[name="password"]', '');
      result = await result.shouldBeEnabled('input[name="email"]');
      result = await result.shouldBeEnabled('input[name="password"]');
      result = await result.shouldBeDisabled('button[type="submit"]');

      expect(browser.assertionCount, equals(9));
    });
  });
}

/// Mock browser implementation for integration testing
class MockIntegrationBrowser extends BrowserAssertions with Browser {
  String _currentUrl = '';
  String _pageTitle = '';
  String _pageSource = '';
  final Map<String, String> _elementTexts = {};
  final Map<String, Map<String, String>> _elementAttributes = {};
  final Set<String> _presentElements = {};
  final Set<String> _checkedElements = {};
  final Set<String> _enabledElements = {};
  int _assertionCount = 0;

  int get assertionCount => _assertionCount;

  void simulateLoginPage() {
    _currentUrl = '/login';
    _pageTitle = 'Login - MyApp';
    _pageSource = 'Welcome back! Please sign in to your account.';
    _presentElements.addAll([
      '#login-form',
      'input[name="email"]',
      'input[name="password"]',
      'input[name="remember"]',
      'button[type="submit"]',
    ]);
    _enabledElements.addAll([
      'input[name="email"]',
      'input[name="password"]',
      'input[name="remember"]',
      'button[type="submit"]',
    ]);
  }

  void simulateFormFilled() {
    _elementAttributes['input[name="email"]'] = {'value': 'user@example.com'};
    _elementAttributes['input[name="password"]'] = {'value': 'password123'};
    _checkedElements.add('input[name="remember"]');
  }

  void simulateSuccessfulLogin() {
    _currentUrl = '/dashboard';
    _pageTitle = 'Dashboard - MyApp';
    _pageSource = 'Welcome, John Doe! Your dashboard is ready.';
    _presentElements.clear();
    _presentElements.addAll(['.user-profile', '.dashboard-content']);
  }

  void simulateErrorPage() {
    _currentUrl = '/error';
    _pageTitle = 'Error - MyApp';
    _pageSource = 'Something went wrong. Please try again later.';
    _presentElements.clear();
    _presentElements.addAll(['.error-message', 'button[type="retry"]']);
    _enabledElements.clear();
    // button[type="retry"] is disabled
  }

  void simulateFormValidationErrors() {
    _currentUrl = '/register';
    _pageTitle = 'Register - MyApp';
    _pageSource =
        'Please correct the following errors: Email is required. Password must be at least 8 characters.';
    _presentElements.clear();
    _presentElements.addAll([
      '.validation-error',
      'input[name="email"]',
      'input[name="password"]',
      'button[type="submit"]',
    ]);
    _enabledElements.clear();
    _enabledElements.addAll(['input[name="email"]', 'input[name="password"]']);
    _elementAttributes['input[name="email"]'] = {'value': ''};
    _elementAttributes['input[name="password"]'] = {'value': ''};
    // submit button is disabled due to validation errors
  }

  // Browser interface implementations
  @override
  Future<String> getCurrentUrl() async => _currentUrl;

  @override
  Future<String> getTitle() async => _pageTitle;

  @override
  Future<String> getPageSource() async => _pageSource;

  @override
  Future<bool> isPresent(String selector) async =>
      _presentElements.contains(selector);

  @override
  Future<MockWebElement> findElement(String selector) async =>
      MockWebElement(selector, this);

  // Assertion implementations that track calls
  @override
  Future<Browser> assertSee(String text) async {
    _assertionCount++;
    if (!_pageSource.contains(text)) {
      throw TestFailure('Expected to see "$text" but it was not found');
    }
    return this;
  }

  @override
  Future<Browser> assertDontSee(String text) async {
    _assertionCount++;
    if (_pageSource.contains(text)) {
      throw TestFailure('Expected not to see "$text" but it was found');
    }
    return this;
  }

  @override
  Future<Browser> assertTitle(String title) async {
    _assertionCount++;
    if (_pageTitle != title) {
      throw TestFailure('Expected title "$title" but got "$_pageTitle"');
    }
    return this;
  }

  @override
  Future<Browser> assertUrlIs(String url) async {
    _assertionCount++;
    if (_currentUrl != url) {
      throw TestFailure('Expected URL "$url" but got "$_currentUrl"');
    }
    return this;
  }

  @override
  Future<Browser> assertPresent(String selector) async {
    _assertionCount++;
    if (!_presentElements.contains(selector)) {
      throw TestFailure('Expected element "$selector" to be present');
    }
    return this;
  }

  @override
  Future<Browser> assertNotPresent(String selector) async {
    _assertionCount++;
    if (_presentElements.contains(selector)) {
      throw TestFailure('Expected element "$selector" not to be present');
    }
    return this;
  }

  @override
  Future<Browser> assertInputValue(String selector, String value) async {
    _assertionCount++;
    final actualValue = _elementAttributes[selector]?['value'];
    if (actualValue != value) {
      throw TestFailure(
        'Expected input "$selector" to have value "$value" but got "$actualValue"',
      );
    }
    return this;
  }

  @override
  Future<Browser> assertChecked(String selector) async {
    _assertionCount++;
    if (!_checkedElements.contains(selector)) {
      throw TestFailure('Expected element "$selector" to be checked');
    }
    return this;
  }

  @override
  Future<Browser> assertEnabled(String selector) async {
    _assertionCount++;
    if (!_enabledElements.contains(selector)) {
      throw TestFailure('Expected element "$selector" to be enabled');
    }
    return this;
  }

  @override
  Future<Browser> assertDisabled(String selector) async {
    _assertionCount++;
    if (_enabledElements.contains(selector)) {
      throw TestFailure('Expected element "$selector" to be disabled');
    }
    return this;
  }

  // Stub implementations for other required methods
  @override
  noSuchMethod(Invocation invocation) => Future.value(this);
}

class MockWebElement {
  final String selector;
  final MockIntegrationBrowser browser;

  MockWebElement(this.selector, this.browser);

  String get text => browser._elementTexts[selector] ?? '';

  Map<String, String> get attributes =>
      browser._elementAttributes[selector] ?? {};

  bool get selected => browser._checkedElements.contains(selector);

  bool get enabled => browser._enabledElements.contains(selector);
}
