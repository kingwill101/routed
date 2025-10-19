import 'dart:async';

import 'package:server_testing/src/browser/interfaces/assertions.dart';
import 'package:server_testing/src/browser/interfaces/dialog.dart';
import 'package:server_testing/src/browser/interfaces/frame.dart';
import 'package:server_testing/src/browser/interfaces/keyboard.dart';
import 'package:server_testing/src/browser/interfaces/mouse.dart';
import 'package:server_testing/src/browser/interfaces/waiter.dart';
import 'package:server_testing/src/browser/interfaces/window.dart';

import 'cookie.dart';
import 'download.dart';
import 'emulation.dart';
import 'local_storage.dart';
import 'network.dart';
import 'session_storage.dart';

/// Browser automation interface for interacting with web pages.
///
/// Defines a unified API for browser automation across both synchronous and
/// asynchronous WebDriver implementations. Provides navigation, DOM manipulation,
/// event simulation, and assertion capabilities.
///
/// Basic usage:
///
/// ```dart
/// // Navigate to a URL
/// await browser.visit('/login');
///
/// // Interact with elements
/// await browser.type('input[name="email"]', 'user@example.com');
/// await browser.type('input[name="password"]', 'password');
/// await browser.click('button[type="submit"]');
///
/// // Wait for elements
/// await browser.waiter.waitFor('.welcome-message');
///
/// // Make assertions
/// await browser.assertSee('Welcome back');
/// await browser.assertPresent('.user-menu');
/// ```
///
/// The interface provides specialized handlers for different aspects:
///
/// - [keyboard]: Keyboard input simulation
/// - [mouse]: Mouse movement and clicking
/// - [dialogs]: Alert and confirmation dialog handling
/// - [frames]: Iframe navigation
/// - [waiter]: Waiting for conditions
/// - [window]: Window size and position management
/// - [cookies]: Cookie manipulation
/// - [localStorage]: Local storage access
/// - [sessionStorage]: Session storage access
/// - [network]: Network request interception
/// - [emulation]: Device emulation
/// - [download]: File download handling
mixin Browser on BrowserAssertions {
  /// Navigates to the specified URL.
  ///
  /// If [url] is relative (doesn't start with http:// or https://),
  /// resolves it against the baseUrl from browser config.
  FutureOr<void> visit(String url);

  /// Navigates back in the browser history.
  FutureOr<void> back();

  /// Navigates forward in the browser history.
  FutureOr<void> forward();

  /// Refreshes the current page.
  FutureOr<void> refresh();

  /// Clicks on an element identified by the selector.
  ///
  /// Throws if no element matches [selector].
  FutureOr<void> click(String selector);

  /// Types text into an input element identified by the selector.
  ///
  /// Throws if no element matches [selector].
  FutureOr<void> type(String selector, String value);

  /// Finds an element in the DOM by its CSS selector.
  ///
  /// Returns the element as WebElement or equivalent, depending on implementation.
  /// Throws if no element matches [selector].
  FutureOr<dynamic> findElement(String selector);

  /// Returns whether an element exists in the DOM.
  FutureOr<bool> isPresent(String selector);

  /// Returns the HTML source of the current page.
  FutureOr<String> getPageSource();

  /// Returns the current URL of the browser.
  FutureOr<String> getCurrentUrl();

  /// Returns the title of the current page.
  FutureOr<String> getTitle();

  /// Executes JavaScript code in the browser context.
  ///
  /// Returns the result of the script execution.
  FutureOr<dynamic> executeScript(String script);

  /// Waits until a condition is true or timeout occurs.
  ///
  /// Throws a timeout exception if the condition isn't met within [timeout].
  FutureOr<void> waitUntil(
    FutureOr<bool> Function() predicate, {
    Duration? timeout,
    Duration interval = const Duration(milliseconds: 100),
  });

  /// Handler for cookie operations.
  Cookie get cookies;

  /// Handler for localStorage operations.
  LocalStorage get localStorage;

  /// Handler for sessionStorage operations.
  SessionStorage get sessionStorage;

  /// Handler for keyboard operations.
  Keyboard get keyboard;

  /// Handler for mouse operations.
  Mouse get mouse;

  /// Handler for dialog operations.
  DialogHandler get dialogs;

  /// Handler for frame operations.
  FrameHandler get frames;

  /// Handler for window operations.
  WindowManager get window;

  /// Handler for waiting operations.
  BrowserWaiter get waiter;

  /// Handler for network operations.
  Network get network;

  /// Handler for device emulation.
  Emulation get emulation;

  /// Handler for download operations.
  Download get download;

  /// Quits the browser and closes all associated windows.
  FutureOr<void> quit();

  // ========================================
  // Laravel Dusk-inspired convenience methods
  // ========================================

  /// Clicks on a link containing the specified text.
  ///
  /// Searches for an anchor tag (`<a>`) that contains the given text
  /// and clicks on it. This is useful for clicking navigation links
  /// or other text-based links.
  ///
  /// Example:
  /// ```dart
  /// await browser.clickLink('About Us');
  /// await browser.clickLink('Sign Out');
  /// ```
  ///
  /// Throws if no link with the specified text is found.
  FutureOr<void> clickLink(String linkText);

  /// Selects an option from a dropdown/select element.
  ///
  /// [selector] is the CSS selector for the select element.
  /// [value] is the value of the option to select.
  ///
  /// Example:
  /// ```dart
  /// await browser.selectOption('select[name="country"]', 'US');
  /// await browser.selectOption('#category', 'electronics');
  /// ```
  FutureOr<void> selectOption(String selector, String value);

  /// Checks a checkbox or radio button.
  ///
  /// [selector] is the CSS selector for the checkbox or radio button.
  ///
  /// Example:
  /// ```dart
  /// await browser.check('input[name="terms"]');
  /// await browser.check('#newsletter-signup');
  /// ```
  FutureOr<void> check(String selector);

  /// Unchecks a checkbox.
  ///
  /// [selector] is the CSS selector for the checkbox.
  ///
  /// Example:
  /// ```dart
  /// await browser.uncheck('input[name="notifications"]');
  /// await browser.uncheck('#marketing-emails');
  /// ```
  FutureOr<void> uncheck(String selector);

  /// Fills multiple form fields at once.
  ///
  /// [data] is a map where keys are CSS selectors and values are the text to type.
  ///
  /// Example:
  /// ```dart
  /// await browser.fillForm({
  ///   'input[name="email"]': 'user@example.com',
  ///   'input[name="password"]': 'secret123',
  ///   'textarea[name="message"]': 'Hello world!',
  /// });
  /// ```
  FutureOr<void> fillForm(Map<String, String> data);

  /// Submits a form.
  ///
  /// If [selector] is provided, submits the specific form matching that selector.
  /// Otherwise, submits the first form found on the page.
  ///
  /// Example:
  /// ```dart
  /// await browser.submitForm(); // Submit first form
  /// await browser.submitForm('#login-form'); // Submit specific form
  /// ```
  FutureOr<void> submitForm([String? selector]);

  /// Uploads a file to a file input element.
  ///
  /// [selector] is the CSS selector for the file input element.
  /// [filePath] is the path to the file to upload.
  ///
  /// Example:
  /// ```dart
  /// await browser.uploadFile('input[type="file"]', '/path/to/document.pdf');
  /// await browser.uploadFile('#avatar-upload', '/path/to/image.jpg');
  /// ```
  FutureOr<void> uploadFile(String selector, String filePath);

  /// Scrolls to a specific element on the page.
  ///
  /// [selector] is the CSS selector for the element to scroll to.
  ///
  /// Example:
  /// ```dart
  /// await browser.scrollTo('#footer');
  /// await browser.scrollTo('.contact-section');
  /// ```
  FutureOr<void> scrollTo(String selector);

  /// Scrolls to the top of the page.
  ///
  /// Example:
  /// ```dart
  /// await browser.scrollToTop();
  /// ```
  FutureOr<void> scrollToTop();

  /// Scrolls to the bottom of the page.
  ///
  /// Example:
  /// ```dart
  /// await browser.scrollToBottom();
  /// ```
  FutureOr<void> scrollToBottom();

  // ========================================
  // Enhanced waiting methods
  // ========================================

  /// Waits for an element to appear in the DOM.
  ///
  /// [selector] is the CSS selector for the element to wait for.
  /// [timeout] is the maximum time to wait (defaults to browser config timeout).
  ///
  /// Example:
  /// ```dart
  /// await browser.waitForElement('.loading-spinner');
  /// await browser.waitForElement('#success-message', timeout: Duration(seconds: 5));
  /// ```
  FutureOr<void> waitForElement(String selector, {Duration? timeout});

  /// Waits for specific text to appear on the page.
  ///
  /// [text] is the text to wait for.
  /// [timeout] is the maximum time to wait (defaults to browser config timeout).
  ///
  /// Example:
  /// ```dart
  /// await browser.waitForText('Welcome back!');
  /// await browser.waitForText('Order confirmed', timeout: Duration(seconds: 10));
  /// ```
  FutureOr<void> waitForText(String text, {Duration? timeout});

  /// Waits for the browser to navigate to a specific URL.
  ///
  /// [url] is the URL to wait for (can be partial).
  /// [timeout] is the maximum time to wait (defaults to browser config timeout).
  ///
  /// Example:
  /// ```dart
  /// await browser.waitForUrl('/dashboard');
  /// await browser.waitForUrl('https://example.com/success');
  /// ```
  FutureOr<void> waitForUrl(String url, {Duration? timeout});

  /// Pauses execution for the specified duration.
  ///
  /// This is useful for debugging or waiting for animations to complete.
  /// Use sparingly in production tests - prefer specific waits when possible.
  ///
  /// [duration] is how long to pause.
  ///
  /// Example:
  /// ```dart
  /// await browser.pause(Duration(seconds: 2));
  /// await browser.pause(Duration(milliseconds: 500));
  /// ```
  FutureOr<void> pause(Duration duration);

  // ========================================
  // Debugging helper methods
  // ========================================

  /// Takes a screenshot of the current page.
  ///
  /// [name] is an optional name for the screenshot file.
  /// If not provided, a timestamp-based name will be used.
  ///
  /// Example:
  /// ```dart
  /// await browser.takeScreenshot(); // Auto-generated name
  /// await browser.takeScreenshot('login-page'); // Custom name
  /// ```
  FutureOr<void> takeScreenshot([String? name]);

  /// Dumps the current page source to the console or log.
  ///
  /// This is useful for debugging when elements are not found
  /// or when the page state is unexpected.
  ///
  /// Example:
  /// ```dart
  /// await browser.dumpPageSource();
  /// ```
  FutureOr<void> dumpPageSource();

  /// Gets the text content of an element.
  ///
  /// [selector] is the CSS selector for the element.
  /// Returns the text content of the element.
  ///
  /// Example:
  /// ```dart
  /// final message = await browser.getElementText('.alert-message');
  /// final title = await browser.getElementText('h1');
  /// ```
  FutureOr<String> getElementText(String selector);

  /// Gets the value of an attribute from an element.
  ///
  /// [selector] is the CSS selector for the element.
  /// [attribute] is the name of the attribute to retrieve.
  /// Returns the attribute value, or null if the attribute doesn't exist.
  ///
  /// Example:
  /// ```dart
  /// final href = await browser.getElementAttribute('a.download', 'href');
  /// final className = await browser.getElementAttribute('.button', 'class');
  /// ```
  FutureOr<String?> getElementAttribute(String selector, String attribute);
}
