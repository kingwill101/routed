import 'dart:async';

import 'browser.dart';

/// Browser assertions interface.
///
/// This abstract class defines a comprehensive set of assertions that can
/// be performed on a browser during testing. Each assertion method returns
/// the browser instance to allow for fluent chaining of assertions.
///
/// The assertions are grouped into categories:
/// - Title assertions
/// - URL assertions
/// - Text assertions
/// - Element assertions
/// - Form assertions
/// - State assertions
/// - Authentication assertions
///
/// ## Example
///
/// ```dart
/// await browser
///   .visit('/profile')
///   .assertTitle('User Profile')
///   .assertSee('Welcome back')
///   .assertVisible('.profile-card')
///   .assertInputValue('input[name="email"]', 'user@example.com');
/// ```
abstract class BrowserAssertions {
  // Title Assertions

  /// Asserts that the page title exactly matches the expected title.
  ///
  /// [title] is the expected title text.
  FutureOr<Browser> assertTitle(String title);

  /// Asserts that the page title contains the specified text.
  ///
  /// [text] is the text that should be present in the title.
  FutureOr<Browser> assertTitleContains(String text);

  // URL Assertions

  /// Asserts that the current URL exactly matches the expected URL.
  ///
  /// [url] is the expected URL.
  FutureOr<Browser> assertUrlIs(String url);

  /// Asserts that the URL path exactly matches the expected path.
  ///
  /// [path] is the expected path portion of the URL.
  FutureOr<Browser> assertPathIs(String path);

  /// Asserts that the URL path begins with the specified prefix.
  ///
  /// [path] is the expected prefix of the URL path.
  FutureOr<Browser> assertPathBeginsWith(String path);

  /// Asserts that the URL path ends with the specified suffix.
  ///
  /// [path] is the expected suffix of the URL path.
  FutureOr<Browser> assertPathEndsWith(String path);

  /// Asserts that the URL query string contains the specified parameter.
  ///
  /// [name] is the name of the query parameter.
  /// [value] is the optional expected value of the query parameter.
  FutureOr<Browser> assertQueryStringHas(String name, [String? value]);

  /// Asserts that the URL query string does not contain the specified parameter.
  ///
  /// [name] is the name of the query parameter that should be absent.
  FutureOr<Browser> assertQueryStringMissing(String name);

  // Text Assertions

  /// Asserts that the page contains the specified text.
  ///
  /// [text] is the text to find on the page.
  FutureOr<Browser> assertSee(String text);

  /// Asserts that the page does not contain the specified text.
  ///
  /// [text] is the text that should not be present on the page.
  FutureOr<Browser> assertDontSee(String text);

  /// Asserts that the specified element contains the given text.
  ///
  /// [selector] is the CSS selector for the element.
  /// [text] is the text to find within the element.
  FutureOr<Browser> assertSeeIn(String selector, String text);

  /// Asserts that the specified element does not contain the given text.
  ///
  /// [selector] is the CSS selector for the element.
  /// [text] is the text that should not be present in the element.
  FutureOr<Browser> assertDontSeeIn(String selector, String text);

  /// Asserts that the specified element contains any text.
  ///
  /// [selector] is the CSS selector for the element.
  FutureOr<Browser> assertSeeAnythingIn(String selector);

  /// Asserts that the specified element contains no text.
  ///
  /// [selector] is the CSS selector for the element.
  FutureOr<Browser> assertSeeNothingIn(String selector);

  // Element Assertions

  /// Asserts that an element matching the selector is present in the DOM.
  ///
  /// [selector] is the CSS selector for the element.
  FutureOr<Browser> assertPresent(String selector);

  /// Asserts that no element matching the selector is present in the DOM.
  ///
  /// [selector] is the CSS selector for the element.
  FutureOr<Browser> assertNotPresent(String selector);

  /// Asserts that an element matching the selector is visible on the page.
  ///
  /// [selector] is the CSS selector for the element.
  FutureOr<Browser> assertVisible(String selector);

  /// Asserts that no element matching the selector is present in the DOM.
  ///
  /// This is an alias for [assertNotPresent].
  ///
  /// [selector] is the CSS selector for the element.
  FutureOr<Browser> assertMissing(String selector);

  /// Asserts that an input field with the specified name is present.
  ///
  /// [name] is the name attribute of the input field.
  FutureOr<Browser> assertInputPresent(String name);

  /// Asserts that no input field with the specified name is present.
  ///
  /// [name] is the name attribute of the input field.
  FutureOr<Browser> assertInputMissing(String name);

  // Form Assertions

  /// Asserts that an input field has the specified value.
  ///
  /// [field] is a CSS selector for the input field.
  /// [value] is the expected value of the input field.
  FutureOr<Browser> assertInputValue(String field, String value);

  /// Asserts that an input field does not have the specified value.
  ///
  /// [field] is a CSS selector for the input field.
  /// [value] is the value that the input field should not have.
  FutureOr<Browser> assertInputValueIsNot(String field, String value);

  /// Asserts that a checkbox or radio button is checked.
  ///
  /// [field] is a CSS selector for the checkbox or radio button.
  FutureOr<Browser> assertChecked(String field);

  /// Asserts that a checkbox or radio button is not checked.
  ///
  /// [field] is a CSS selector for the checkbox or radio button.
  FutureOr<Browser> assertNotChecked(String field);

  /// Asserts that a radio button with the specified name and value is selected.
  ///
  /// [field] is the name of the radio button group.
  /// [value] is the value of the radio button that should be selected.
  FutureOr<Browser> assertRadioSelected(String field, String value);

  /// Asserts that a radio button with the specified name and value is not selected.
  ///
  /// [field] is the name of the radio button group.
  /// [value] is the value of the radio button that should not be selected.
  FutureOr<Browser> assertRadioNotSelected(String field, String value);

  /// Asserts that an option with the specified value is selected in a select element.
  ///
  /// [field] is a CSS selector for the select element.
  /// [value] is the value of the option that should be selected.
  FutureOr<Browser> assertSelected(String field, String value);

  /// Asserts that an option with the specified value is not selected in a select element.
  ///
  /// [field] is a CSS selector for the select element.
  /// [value] is the value of the option that should not be selected.
  FutureOr<Browser> assertNotSelected(String field, String value);

  // State Assertions

  /// Asserts that a form field is enabled.
  ///
  /// [field] is a CSS selector for the form field.
  FutureOr<Browser> assertEnabled(String field);

  /// Asserts that a form field is disabled.
  ///
  /// [field] is a CSS selector for the form field.
  FutureOr<Browser> assertDisabled(String field);

  /// Asserts that a form field has focus.
  ///
  /// [field] is a CSS selector for the form field.
  FutureOr<Browser> assertFocused(String field);

  /// Asserts that a form field does not have focus.
  ///
  /// [field] is a CSS selector for the form field.
  FutureOr<Browser> assertNotFocused(String field);

  // Auth Assertions

  /// Asserts that the user is authenticated.
  ///
  /// [guard] is an optional authentication guard name.
  FutureOr<Browser> assertAuthenticated([String? guard]);

  /// Asserts that the user is a guest (not authenticated).
  ///
  /// [guard] is an optional authentication guard name.
  FutureOr<Browser> assertGuest([String? guard]);

  // ========================================
  // Laravel Dusk-inspired assertion aliases
  // ========================================

  /// Laravel Dusk-style alias for [assertSee].
  ///
  /// Asserts that the page contains the specified text.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldSee('Welcome back!');
  /// ```
  FutureOr<Browser> shouldSee(String text) => assertSee(text);

  /// Laravel Dusk-style alias for [assertDontSee].
  ///
  /// Asserts that the page does not contain the specified text.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldNotSee('Error occurred');
  /// ```
  FutureOr<Browser> shouldNotSee(String text) => assertDontSee(text);

  /// Laravel Dusk-style alias for [assertTitle].
  ///
  /// Asserts that the page title exactly matches the expected title.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldHaveTitle('Dashboard - MyApp');
  /// ```
  FutureOr<Browser> shouldHaveTitle(String title) => assertTitle(title);

  /// Laravel Dusk-style alias for [assertUrlIs].
  ///
  /// Asserts that the current URL exactly matches the expected URL.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldBeOn('/dashboard');
  /// ```
  FutureOr<Browser> shouldBeOn(String url) => assertUrlIs(url);

  /// Laravel Dusk-style alias for [assertPresent].
  ///
  /// Asserts that an element matching the selector is present in the DOM.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldHaveElement('.success-message');
  /// ```
  FutureOr<Browser> shouldHaveElement(String selector) =>
      assertPresent(selector);

  /// Laravel Dusk-style alias for [assertNotPresent].
  ///
  /// Asserts that no element matching the selector is present in the DOM.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldNotHaveElement('.error-message');
  /// ```
  FutureOr<Browser> shouldNotHaveElement(String selector) =>
      assertNotPresent(selector);

  /// Laravel Dusk-style alias for [assertInputValue].
  ///
  /// Asserts that an input field has the specified value.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldHaveValue('input[name="email"]', 'user@example.com');
  /// ```
  FutureOr<Browser> shouldHaveValue(String selector, String value) =>
      assertInputValue(selector, value);

  /// Laravel Dusk-style alias for [assertChecked].
  ///
  /// Asserts that a checkbox or radio button is checked.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldBeChecked('input[name="terms"]');
  /// ```
  FutureOr<Browser> shouldBeChecked(String selector) => assertChecked(selector);

  /// Laravel Dusk-style alias for [assertEnabled].
  ///
  /// Asserts that a form field is enabled.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldBeEnabled('button[type="submit"]');
  /// ```
  FutureOr<Browser> shouldBeEnabled(String selector) => assertEnabled(selector);

  /// Laravel Dusk-style alias for [assertDisabled].
  ///
  /// Asserts that a form field is disabled.
  ///
  /// Example:
  /// ```dart
  /// await browser.shouldBeDisabled('input[name="readonly"]');
  /// ```
  FutureOr<Browser> shouldBeDisabled(String selector) =>
      assertDisabled(selector);
}
