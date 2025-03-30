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
}
