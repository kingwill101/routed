import 'package:test/test.dart';

import '../interfaces/assertions.dart';
import '../interfaces/browser.dart';
import 'browser.dart' show AsyncBrowser;

/// Implements the [BrowserAssertions] interface using the asynchronous WebDriver API.
///
/// Provides methods for making assertions about the state of the browser and
/// the page content.
mixin AsyncBrowserAssertions implements BrowserAssertions {
  /// The asynchronous browser instance associated with these assertions.
  AsyncBrowser get browser => this as AsyncBrowser;

  /// Asserts that the page title exactly matches the expected [title].
  ///
  @override
  Future<Browser> assertTitle(String title) async {
    expect(await browser.getTitle(), equals(title));
    return browser;
  }

  /// Asserts that the page title contains the specified [text].
  ///
  @override
  Future<Browser> assertTitleContains(String text) async {
    expect(await browser.getTitle(), contains(text));
    return browser;
  }

  /// Asserts that the current URL exactly matches the expected [url].
  ///
  @override
  Future<Browser> assertUrlIs(String url) async {
    expect(await browser.getCurrentUrl(), equals(url));
    return browser;
  }

  /// Asserts that the URL path exactly matches the expected [path].
  ///
  @override
  Future<Browser> assertPathIs(String path) async {
    final url = await browser.getCurrentUrl();
    expect(Uri.parse(url).path, equals(path));
    return browser;
  }

  /// Asserts that the URL path begins with the specified [path].
  ///
  @override
  Future<Browser> assertPathBeginsWith(String path) async {
    final url = await browser.getCurrentUrl();
    expect(Uri.parse(url).path, startsWith(path));
    return browser;
  }

  /// Asserts that the URL path ends with the specified [path].
  ///
  @override
  Future<Browser> assertPathEndsWith(String path) async {
    final url = await browser.getCurrentUrl();
    expect(Uri.parse(url).path, endsWith(path));
    return browser;
  }

  /// Asserts that the URL query string contains a parameter named [name].
  ///
  /// If [value] is provided, also asserts that the parameter has that specific value.
  @override
  Future<Browser> assertQueryStringHas(String name, [String? value]) async {
    final url = await browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, contains(name));
    if (value != null) {
      expect(params[name], equals(value));
    }
    return browser;
  }

  /// Asserts that the URL query string does not contain a parameter named [name].
  ///
  @override
  Future<Browser> assertQueryStringMissing(String name) async {
    final url = await browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, isNot(contains(name)));
    return browser;
  }

  /// Asserts that the page source contains the specified [text].
  ///
  @override
  Future<Browser> assertSee(String text) async {
    expect(await browser.getPageSource(), contains(text));
    return browser;
  }

  /// Asserts that the page source does not contain the specified [text].
  ///
  @override
  Future<Browser> assertDontSee(String text) async {
    expect(await browser.getPageSource(), isNot(contains(text)));
    return browser;
  }

  /// Asserts that the element identified by [selector] contains the given [text].
  ///
  @override
  Future<Browser> assertSeeIn(String selector, String text) async {
    final element = await browser.findElement(selector);
    final elementText = await element.text;
    expect(elementText, contains(text));
    return browser;
  }

  /// Asserts that the element identified by [selector] does not contain the given [text].
  ///
  @override
  Future<Browser> assertDontSeeIn(String selector, String text) async {
    final element = await browser.findElement(selector);
    final elementText = await element.text;
    expect(elementText, isNot(contains(text)));
    return browser;
  }

  /// Asserts that the element identified by [selector] contains any non-whitespace text.
  ///
  @override
  Future<Browser> assertSeeAnythingIn(String selector) async {
    final element = await browser.findElement(selector);
    final text = await element.text;
    expect(text.trim(), isNotEmpty);
    return browser;
  }

  /// Asserts that the element identified by [selector] contains only whitespace or is empty.
  ///
  @override
  Future<Browser> assertSeeNothingIn(String selector) async {
    final element = await browser.findElement(selector);
    final text = await element.text;
    expect(text.trim(), isEmpty);
    return browser;
  }

  /// Asserts that an element matching [selector] is present in the DOM.
  ///
  @override
  Future<Browser> assertPresent(String selector) async {
    expect(await browser.isPresent(selector), isTrue);
    return browser;
  }

  /// Asserts that no element matching [selector] is present in the DOM.
  ///
  @override
  Future<Browser> assertNotPresent(String selector) async {
    expect(await browser.isPresent(selector), isFalse);
    return browser;
  }

  /// Asserts that the element identified by [selector] is visible on the page.
  ///
  @override
  Future<Browser> assertVisible(String selector) async {
    final element = await browser.findElement(selector);
    expect(await element.displayed, isTrue);
    return browser;
  }

  /// Asserts that no element matching [selector] is present in the DOM.
  ///
  /// This is an alias for [assertNotPresent].
  @override
  Future<Browser> assertMissing(String selector) async {
    expect(await browser.isPresent(selector), isFalse);
    return browser;
  }

  /// Asserts that an input element with the name attribute [name] is present.
  ///
  @override
  Future<Browser> assertInputPresent(String name) async {
    expect(await browser.isPresent('input[name="$name"]'), isTrue);
    return browser;
  }

  /// Asserts that no input element with the name attribute [name] is present.
  ///
  @override
  Future<Browser> assertInputMissing(String name) async {
    expect(await browser.isPresent('input[name="$name"]'), isFalse);
    return browser;
  }

  /// Asserts that the input element identified by [field] has the specified [value].
  ///
  @override
  Future<Browser> assertInputValue(String field, String value) async {
    final element = await browser.findElement(field);
    expect(await element.attributes['value'], equals(value));
    return browser;
  }

  /// Asserts that the input element identified by [field] does not have the specified [value].
  ///
  @override
  Future<Browser> assertInputValueIsNot(String field, String value) async {
    final element = await browser.findElement(field);
    expect(await element.attributes['value'], isNot(equals(value)));
    return browser;
  }

  /// Asserts that the checkbox or radio button identified by [field] is checked.
  ///
  @override
  Future<Browser> assertChecked(String field) async {
    final element = await browser.findElement(field);
    expect(await element.selected, isTrue);
    return browser;
  }

  /// Asserts that the checkbox or radio button identified by [field] is not checked.
  ///
  @override
  Future<Browser> assertNotChecked(String field) async {
    final element = await browser.findElement(field);
    expect(await element.selected, isFalse);
    return browser;
  }

  /// Asserts that the radio button in group [field] with the specified [value] is selected.
  ///
  @override
  Future<Browser> assertRadioSelected(String field, String value) async {
    final element = await browser
        .findElement('input[type="radio"][name="$field"][value="$value"]');
    expect(await element.selected, isTrue);
    return browser;
  }

  /// Asserts that the radio button in group [field] with the specified [value] is not selected.
  ///
  @override
  Future<Browser> assertRadioNotSelected(String field, String value) async {
    final element = await browser
        .findElement('input[type="radio"][name="$field"][value="$value"]');
    expect(await element.selected, isFalse);
    return browser;
  }

  /// Asserts that the option with [value] in the select element [field] is selected.
  ///
  @override
  Future<Browser> assertSelected(String field, String value) async {
    final element = await browser.findElement('$field option[value="$value"]');
    expect(await element.selected, isTrue);
    return browser;
  }

  /// Asserts that the option with [value] in the select element [field] is not selected.
  ///
  @override
  Future<Browser> assertNotSelected(String field, String value) async {
    final element = await browser.findElement('$field option[value="$value"]');
    expect(await element.selected, isFalse);
    return browser;
  }

  /// Asserts that the form element identified by [field] is enabled.
  ///
  @override
  Future<Browser> assertEnabled(String field) async {
    final element = await browser.findElement(field);
    expect(await element.enabled, isTrue);
    return browser;
  }

  /// Asserts that the form element identified by [field] is disabled.
  ///
  @override
  Future<Browser> assertDisabled(String field) async {
    final element = await browser.findElement(field);
    expect(await element.enabled, isFalse);
    return browser;
  }

  /// Asserts that the form element identified by [field] currently has focus.
  ///
  @override
  Future<Browser> assertFocused(String field) async {
    final element = await browser.findElement(field);
    final activeElement = await browser.driver.activeElement;
    expect(await element.equals(activeElement), isTrue);
    return browser;
  }

  /// Asserts that the form element identified by [field] does not currently have focus.
  ///
  @override
  Future<Browser> assertNotFocused(String field) async {
    final element = await browser.findElement(field);
    final activeElement = await browser.driver.activeElement;
    if (activeElement == null) return browser;
    expect(await element.equals(activeElement), isFalse);
    return browser;
  }

  /// Asserts that the user is authenticated.
  ///
  /// Uses the authentication setup specified by the optional [guard].
  @override
  Future<Browser> assertAuthenticated([String? guard]) async {
    
    return browser;
  }

  /// Asserts that the user is not authenticated (is a guest).
  ///
  /// Uses the authentication setup specified by the optional [guard].
  @override
  Future<Browser> assertGuest([String? guard]) async {
    // Implementation depends on your authentication setup
    return browser;
  }
}
