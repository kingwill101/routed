import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';

/// Base class for the Page Object Pattern.
///
/// The Page class is part of the Page Object Pattern, a design pattern that
/// creates an object representation of each page in your application. This
/// abstraction helps separate test logic from page implementation details,
/// making tests more maintainable and readable.
///
/// Each page class encapsulates the structure of a specific page, including
/// its URL, elements, and common interactions.
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

  /// Creates a new page with the specified browser.
  Page(this.browser);

  /// The URL of this page.
  ///
  /// This is used by [navigate] to go to the page and by [assertOnPage]
  /// to verify the browser is on this page.
  String get url;

  /// Navigates to this page's URL.
  ///
  /// This method uses the browser's [visit] method with the page's [url].
  FutureOr<void> navigate() => browser.visit(url);

  /// Asserts that the browser is currently on this page.
  ///
  /// This method verifies that the current URL matches the page's [url].
  Future<void> assertOnPage() async {
    await browser.assertUrlIs(url);
  }
}
