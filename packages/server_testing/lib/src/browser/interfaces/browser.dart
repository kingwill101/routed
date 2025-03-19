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

/// Core browser automation interface.
///
/// This interface defines the API for interacting with a web browser during testing.
/// It provides methods for navigation, DOM manipulation, event simulation, and assertions.
/// The [Browser] interface is implemented by both synchronous and asynchronous WebDriver
/// implementations, providing a unified API regardless of the underlying implementation.
///
/// The interface mixes in [BrowserAssertions] to provide fluent assertions about
/// the browser's state.
///
/// ## Basic Usage
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
/// ## Advanced Features
///
/// The browser interface provides access to specialized handlers for different
/// aspects of browser automation:
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
/// - [network]: Network request/response interception
/// - [emulation]: Device emulation
/// - [download]: File download handling
mixin Browser on BrowserAssertions {
  /// Navigates to the specified URL.
  ///
  /// If the URL is relative (doesn't start with http:// or https://),
  /// it will be resolved relative to the baseUrl specified in the browser config.
  ///
  /// [url] is the URL to navigate to.
  FutureOr<void> visit(String url);

  /// Navigates back in the browser history.
  FutureOr<void> back();

  /// Navigates forward in the browser history.
  FutureOr<void> forward();

  /// Refreshes the current page.
  FutureOr<void> refresh();

  /// Clicks on an element identified by the selector.
  ///
  /// [selector] is a CSS selector that identifies the element to click.
  FutureOr<void> click(String selector);

  /// Types text into an input element identified by the selector.
  ///
  /// [selector] is a CSS selector that identifies the input element.
  /// [value] is the text to type into the input.
  FutureOr<void> type(String selector, String value);

  /// Finds an element in the DOM by its CSS selector.
  ///
  /// [selector] is the CSS selector to find the element.
  ///
  /// Returns the element if found. The return type depends on the specific
  /// implementation (WebElement for WebDriver).
  ///
  /// Throws an exception if the element is not found.
  FutureOr<dynamic> findElement(String selector);

  /// Checks if an element is present in the DOM.
  ///
  /// [selector] is the CSS selector to find the element.
  ///
  /// Returns true if the element is present, false otherwise.
  FutureOr<bool> isPresent(String selector);

  /// Gets the HTML source of the current page.
  FutureOr<String> getPageSource();

  /// Gets the current URL of the browser.
  FutureOr<String> getCurrentUrl();

  /// Gets the title of the current page.
  FutureOr<String> getTitle();

  /// Executes JavaScript code in the browser context.
  ///
  /// [script] is the JavaScript code to execute.
  ///
  /// Returns the result of the script execution.
  FutureOr<dynamic> executeScript(String script);

  /// Waits until a condition is true or a timeout occurs.
  ///
  /// [predicate] is a function that returns a boolean or Future<bool>.
  /// [timeout] is the maximum time to wait for the condition.
  /// [interval] is the interval between checks.
  ///
  /// Throws a timeout exception if the condition is not met within the timeout.
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
}
