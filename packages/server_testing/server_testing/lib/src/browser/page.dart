import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';

/// A page object representing a specific page in a web application.
///
/// Implements the Page Object Pattern by encapsulating page structure, elements,
/// and interactions for a specific page. Helps separate test logic from page
/// implementation details.
///
/// ## Example
///
/// ```dart
/// class LoginPage extends Page {
///   LoginPage(Browser browser) : super(browser);
///
///   @override
///   String get url => '/login';
///
///   // Page elements
///   String get emailInput => 'input[name="email"]';
///   String get passwordInput => 'input[name="password"]';
///   String get submitButton => 'button[type="submit"]';
///
///   // Page interactions
///   Future<void> login({required String email, required String password}) async {
///     await browser.type(emailInput, email);
///     await browser.type(passwordInput, password);
///     await browser.click(submitButton);
///   }
///
///   // Page assertions
///   Future<void> assertHasError(String message) async {
///     await browser.assertSeeIn('.error-message', message);
///   }
/// }
/// ```
///
/// ## Usage in Tests
///
/// ```dart
/// void main() {
///   browserTest('user can log in', (browser) async {
///     final loginPage = LoginPage(browser);
///     await loginPage.navigate();
///
///     await loginPage.login(
///       email: 'user@example.com',
///       password: 'password123',
///     );
///
///     // Assert we're redirected to dashboard
///     await DashboardPage(browser).assertOnPage();
///   });
/// }
/// ```
abstract class Page {
  /// The browser instance for interacting with the page.
  final Browser browser;

  /// Creates a new page with the given browser.
  Page(this.browser);

  /// The URL of this page.
  ///
  /// Used by [navigate] to visit the page and by [assertOnPage]
  /// to verify the current location.
  String get url;

  /// Navigates to this page's URL.
  ///
  /// Uses the browser's [visit] method with this page's [url].
  FutureOr<void> navigate() => browser.visit(url);

  /// Asserts that the browser is currently on this page.
  ///
  /// Verifies that the current URL matches this page's [url].
  Future<void> assertOnPage() async {
    await browser.assertUrlIs(url);
  }

  /// Waits for the page to fully load.
  ///
  /// This method waits for the page's body element to be present,
  /// which indicates the page has loaded. Useful after navigation
  /// or when waiting for dynamic content to appear.
  ///
  /// [timeout] is the maximum time to wait. If not provided,
  /// uses the browser's default timeout configuration.
  ///
  /// Example:
  /// ```dart
  /// final loginPage = LoginPage(browser);
  /// await loginPage.navigate();
  /// await loginPage.waitForLoad(); // Ensure page is fully loaded
  /// ```
  FutureOr<void> waitForLoad({Duration? timeout}) async {
    await browser.waitForElement('body', timeout: timeout);
  }

  /// Fills a form field with the specified value.
  ///
  /// This is a convenience method that wraps the browser's [type] method
  /// with page-specific context. Useful for creating readable page object
  /// methods that encapsulate form interactions.
  ///
  /// [selector] is the CSS selector for the form field.
  /// [value] is the text to type into the field.
  ///
  /// Example:
  /// ```dart
  /// class LoginPage extends Page {
  ///   Future<void> enterEmail(String email) async {
  ///     await fillField('#email', email);
  ///   }
  ///
  ///   Future<void> enterPassword(String password) async {
  ///     await fillField('#password', password);
  ///   }
  /// }
  /// ```
  FutureOr<void> fillField(String selector, String value) async {
    await browser.type(selector, value);
  }

  /// Clicks a button element.
  ///
  /// This is a convenience method that wraps the browser's [click] method
  /// with page-specific context. Useful for creating readable page object
  /// methods that encapsulate button interactions.
  ///
  /// [selector] is the CSS selector for the button element.
  ///
  /// Example:
  /// ```dart
  /// class LoginPage extends Page {
  ///   Future<void> submitLogin() async {
  ///     await clickButton('#login-button');
  ///   }
  ///
  ///   Future<void> cancelLogin() async {
  ///     await clickButton('.cancel-btn');
  ///   }
  /// }
  /// ```
  FutureOr<void> clickButton(String selector) async {
    await browser.click(selector);
  }
}
