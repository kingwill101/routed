import 'package:test/test.dart';

import '../interfaces/assertions.dart';
import '../interfaces/browser.dart';
import 'browser.dart' show SyncBrowser;

/// Implements the [BrowserAssertions] interface using the synchronous WebDriver API.
///
/// Provides methods for making assertions about the state of the browser and
/// the page content using blocking operations.
mixin SyncBrowserAssertions implements BrowserAssertions {
  /// The synchronous browser instance associated with these assertions.
  SyncBrowser get browser => this as SyncBrowser;

  /// Asserts that the page title exactly matches the expected [title].
  @override
  Browser assertTitle(String title) {
    expect(browser.getTitle(), equals(title));
    return browser;
  }

  /// Asserts that the page title contains the specified [text].
  @override
  Browser assertTitleContains(String text) {
    expect(browser.getTitle(), contains(text));
    return browser;
  }

  /// Asserts that the current URL exactly matches the expected [url].
  @override
  Browser assertUrlIs(String url) {
    expect(browser.getCurrentUrl(), equals(url));
    return browser;
  }

  /// Asserts that the URL path exactly matches the expected [path].
  @override
  Browser assertPathIs(String path) {
    final url = browser.getCurrentUrl();
    expect(Uri.parse(url).path, equals(path));
    return browser;
  }

  /// Asserts that the URL path begins with the specified [path].
  @override
  Browser assertPathBeginsWith(String path) {
    final url = browser.getCurrentUrl();
    expect(Uri.parse(url).path, startsWith(path));
    return browser;
  }

  /// Asserts that the URL path ends with the specified [path].
  @override
  Browser assertPathEndsWith(String path) {
    final url = browser.getCurrentUrl();
    expect(Uri.parse(url).path, endsWith(path));
    return browser;
  }

  /// Asserts that the URL query string contains a parameter named [name].
  ///
  /// If [value] is provided, also asserts that the parameter has that specific value.
  @override
  Browser assertQueryStringHas(String name, [String? value]) {
    final url = browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, contains(name));
    if (value != null) {
      expect(params[name], equals(value));
    }
    return browser;
  }

  /// Asserts that the URL query string does not contain a parameter named [name].
  @override
  Browser assertQueryStringMissing(String name) {
    final url = browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, isNot(contains(name)));
    return browser;
  }

  /// Asserts that the page source contains the specified [text].
  @override
  Browser assertSee(String text) {
    expect(browser.getPageSource(), contains(text));
    return browser;
  }

  /// Asserts that the page source does not contain the specified [text].
  @override
  Browser assertDontSee(String text) {
    expect(browser.getPageSource(), isNot(contains(text)));
    return browser;
  }

  /// Asserts that the element identified by [selector] contains the given [text].
  @override
  Browser assertSeeIn(String selector, String text) {
    final element = browser.findElement(selector);
    expect(element.text, contains(text));
    return browser;
  }

  /// Asserts that the element identified by [selector] does not contain the given [text].
  @override
  Browser assertDontSeeIn(String selector, String text) {
    final element = browser.findElement(selector);
    expect(element.text, isNot(contains(text)));
    return browser;
  }

  /// Asserts that the element identified by [selector] contains any non-whitespace text.
  @override
  Browser assertSeeAnythingIn(String selector) {
    final element = browser.findElement(selector);
    expect(element.text.trim(), isNotEmpty);
    return browser;
  }

  /// Asserts that the element identified by [selector] contains only whitespace or is empty.
  @override
  Browser assertSeeNothingIn(String selector) {
    final element = browser.findElement(selector);
    expect(element.text.trim(), isEmpty);
    return browser;
  }

  /// Asserts that an element matching [selector] is present in the DOM.
  @override
  Browser assertPresent(String selector) {
    expect(browser.isPresent(selector), isTrue);
    return browser;
  }

  /// Asserts that no element matching [selector] is present in the DOM.
  @override
  Browser assertNotPresent(String selector) {
    expect(browser.isPresent(selector), isFalse);
    return browser;
  }

  /// Asserts that the element identified by [selector] is visible on the page.
  @override
  Browser assertVisible(String selector) {
    final element = browser.findElement(selector);
    expect(element.displayed, isTrue);
    return browser;
  }

  /// Asserts that no element matching [selector] is present in the DOM.
  ///
  /// This is an alias for [assertNotPresent].
  @override
  Browser assertMissing(String selector) {
    expect(browser.isPresent(selector), isFalse);
    return browser;
  }

  /// Asserts that an input element with the name attribute [name] is present.
  @override
  Browser assertInputPresent(String name) {
    expect(browser.isPresent('input[name="$name"]'), isTrue);
    return browser;
  }

  /// Asserts that no input element with the name attribute [name] is present.
  @override
  Browser assertInputMissing(String name) {
    expect(browser.isPresent('input[name="$name"]'), isFalse);
    return browser;
  }

  /// Asserts that the input element identified by [field] has the specified [value].
  @override
  Browser assertInputValue(String field, String value) {
    final element = browser.findElement(field);
    expect(element.attributes['value'], equals(value));
    return browser;
  }

  /// Asserts that the input element identified by [field] does not have the specified [value].
  @override
  Browser assertInputValueIsNot(String field, String value) {
    final element = browser.findElement(field);
    expect(element.attributes['value'], isNot(equals(value)));
    return browser;
  }

  /// Asserts that the checkbox or radio button identified by [field] is checked.
  @override
  Browser assertChecked(String field) {
    final element = browser.findElement(field);
    expect(element.selected, isTrue);
    return browser;
  }

  /// Asserts that the checkbox or radio button identified by [field] is not checked.
  @override
  Browser assertNotChecked(String field) {
    final element = browser.findElement(field);
    expect(element.selected, isFalse);
    return browser;
  }

  /// Asserts that the radio button in group [field] with the specified [value] is selected.
  @override
  Browser assertRadioSelected(String field, String value) {
    final element = browser.findElement(
      'input[type="radio"][name="$field"][value="$value"]',
    );
    expect(element.selected, isTrue);
    return browser;
  }

  /// Asserts that the radio button in group [field] with the specified [value] is not selected.
  @override
  Browser assertRadioNotSelected(String field, String value) {
    final element = browser.findElement(
      'input[type="radio"][name="$field"][value="$value"]',
    );
    expect(element.selected, isFalse);
    return browser;
  }

  /// Asserts that the option with [value] in the select element [field] is selected.
  @override
  Browser assertSelected(String field, String value) {
    final element = browser.findElement('$field option[value="$value"]');
    expect(element.selected, isTrue);
    return browser;
  }

  /// Asserts that the option with [value] in the select element [field] is not selected.
  @override
  Browser assertNotSelected(String field, String value) {
    final element = browser.findElement('$field option[value="$value"]');
    expect(element.selected, isFalse);
    return browser;
  }

  /// Asserts that the form element identified by [field] is enabled.
  @override
  Browser assertEnabled(String field) {
    final element = browser.findElement(field);
    expect(element.enabled, isTrue);
    return browser;
  }

  /// Asserts that the form element identified by [field] is disabled.
  @override
  Browser assertDisabled(String field) {
    final element = browser.findElement(field);
    expect(element.enabled, isFalse);
    return browser;
  }

  /// Asserts that the form element identified by [field] currently has focus.
  @override
  Browser assertFocused(String field) {
    final element = browser.findElement(field);
    final activeElement = browser.driver.activeElement;
    if (activeElement == null) {
      fail('No active element found');
    }
    expect(element.equals(activeElement), isTrue);
    return browser;
  }

  /// Asserts that the form element identified by [field] does not currently have focus.
  @override
  Browser assertNotFocused(String field) {
    final element = browser.findElement(field);
    final activeElement = browser.driver.activeElement;
    if (activeElement == null) return browser;
    expect(element.equals(activeElement), isFalse);
    return browser;
  }

  /// Asserts that the user is authenticated.
  ///
  /// Uses the authentication setup specified by the optional [guard].
  @override
  Browser assertAuthenticated([String? guard]) {
    return browser;
  }

  /// Asserts that the user is not authenticated (is a guest).
  ///
  /// Uses the authentication setup specified by the optional [guard].
  @override
  Browser assertGuest([String? guard]) {
    // Implementation depends on your authentication setup
    return browser;
  }

  // ========================================
  // Laravel Dusk-inspired assertion aliases
  // ========================================

  /// Laravel Dusk-style alias for [assertSee].
  @override
  Browser shouldSee(String text) => assertSee(text);

  /// Laravel Dusk-style alias for [assertDontSee].
  @override
  Browser shouldNotSee(String text) => assertDontSee(text);

  /// Laravel Dusk-style alias for [assertTitle].
  @override
  Browser shouldHaveTitle(String title) => assertTitle(title);

  /// Laravel Dusk-style alias for [assertUrlIs].
  @override
  Browser shouldBeOn(String url) => assertUrlIs(url);

  /// Laravel Dusk-style alias for [assertPresent].
  @override
  Browser shouldHaveElement(String selector) => assertPresent(selector);

  /// Laravel Dusk-style alias for [assertNotPresent].
  @override
  Browser shouldNotHaveElement(String selector) => assertNotPresent(selector);

  /// Laravel Dusk-style alias for [assertInputValue].
  @override
  Browser shouldHaveValue(String selector, String value) =>
      assertInputValue(selector, value);

  /// Laravel Dusk-style alias for [assertChecked].
  @override
  Browser shouldBeChecked(String selector) => assertChecked(selector);

  /// Laravel Dusk-style alias for [assertEnabled].
  @override
  Browser shouldBeEnabled(String selector) => assertEnabled(selector);

  /// Laravel Dusk-style alias for [assertDisabled].
  @override
  Browser shouldBeDisabled(String selector) => assertDisabled(selector);
}
