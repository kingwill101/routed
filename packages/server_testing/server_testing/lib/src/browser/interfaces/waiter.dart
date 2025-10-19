import 'dart:async';

typedef WaiterCallback = FutureOr<void> Function();

abstract class BrowserWaiter {
  FutureOr<void> wait(Duration timeout);

  FutureOr<void> waitFor(String selector, [Duration? timeout]);

  FutureOr<void> waitUntilMissing(String selector, [Duration? timeout]);

  FutureOr<void> waitForText(String text, [Duration? timeout]);

  FutureOr<void> waitForLocation(String path, [Duration? timeout]);

  FutureOr<void> waitForReload(WaiterCallback callback);

  // ========================================
  // Enhanced waiting methods
  // ========================================

  /// Waits for an element to appear in the DOM.
  ///
  /// This is an alias for [waitFor] with enhanced documentation.
  ///
  /// [selector] is the CSS selector for the element to wait for.
  /// [timeout] is the maximum time to wait (defaults to browser config timeout).
  ///
  /// Example:
  /// ```dart
  /// await browser.waiter.waitForElement('.loading-spinner');
  /// await browser.waiter.waitForElement('#success-message', Duration(seconds: 5));
  /// ```
  FutureOr<void> waitForElement(String selector, {Duration? timeout}) =>
      waitFor(selector, timeout);

  /// Waits for the browser to navigate to a specific URL.
  ///
  /// This is an alias for [waitForLocation] with enhanced documentation.
  ///
  /// [url] is the URL to wait for (can be partial).
  /// [timeout] is the maximum time to wait (defaults to browser config timeout).
  ///
  /// Example:
  /// ```dart
  /// await browser.waiter.waitForUrl('/dashboard');
  /// await browser.waiter.waitForUrl('https://example.com/success');
  /// ```
  FutureOr<void> waitForUrl(String url, {Duration? timeout}) =>
      waitForLocation(url, timeout);

  /// Pauses execution for the specified duration.
  ///
  /// This is useful for debugging or waiting for animations to complete.
  /// Use sparingly in production tests - prefer specific waits when possible.
  ///
  /// [duration] is how long to pause.
  ///
  /// Example:
  /// ```dart
  /// await browser.waiter.pause(Duration(seconds: 2));
  /// await browser.waiter.pause(Duration(milliseconds: 500));
  /// ```
  FutureOr<void> pause(Duration duration) => wait(duration);
}
