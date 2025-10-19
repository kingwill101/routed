import 'dart:async';
import 'dart:io' show sleep;

import 'package:webdriver/sync_core.dart' show TimeoutException;

import '../interfaces/waiter.dart';
import 'browser.dart';

/// Provides synchronous methods for waiting for specific conditions in the browser.
///
/// Uses polling with `sleep`, which blocks the current isolate. Prefer asynchronous
/// waiting ([AsyncBrowserWaiter]) when possible in asynchronous test code.
class SyncBrowserWaiter implements BrowserWaiter {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;

  /// The default timeout duration for wait operations if not specified explicitly.
  final Duration defaultTimeout;

  /// Creates a synchronous waiter for the given [browser].
  ///
  /// Uses the browser's configuration [defaultWaitTimeout] as the default timeout
  /// for wait operations when no specific timeout is provided.
  SyncBrowserWaiter(this.browser)
    : defaultTimeout = browser.config.defaultWaitTimeout;

  /// Waits for an element matching [selector] to be present in the DOM.
  ///
  /// Uses polling with `sleep`. Uses [defaultTimeout] if [timeout] is not
  /// provided. Throws a [TimeoutException] if the element is not found
  /// within the timeout period. This is a blocking operation.
  @override
  void waitFor(String selector, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(
      () => browser.isPresent(selector),
      timeout: timeout,
      operation: 'Wait for element',
      selector: selector,
    );
  }

  /// Waits until no element matching [selector] is present in the DOM.
  ///
  /// Uses polling with `sleep`. Uses [defaultTimeout] if [timeout] is not
  /// provided. Throws a [TimeoutException] if the element still exists after
  /// the timeout period. This is a blocking operation.
  @override
  void waitUntilMissing(String selector, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(
      () => !browser.isPresent(selector),
      timeout: timeout,
      operation: 'Wait for element to disappear',
      selector: selector,
    );
  }

  /// Waits for the page source to contain the specified [text].
  ///
  /// Uses polling with `sleep`. Uses [defaultTimeout] if [timeout] is not
  /// provided. Throws a [TimeoutException] if the text is not found within
  /// the timeout period. This is a blocking operation.
  @override
  void waitForText(String text, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(
      () {
        final source = browser.getPageSource();
        return source.contains(text);
      },
      timeout: timeout,
      operation: 'Wait for text "$text"',
    );
  }

  /// Waits for the current URL path to exactly match the specified [path].
  ///
  /// Uses polling with `sleep`. Uses [defaultTimeout] if [timeout] is not
  /// provided. Throws a [TimeoutException] if the path does not match within
  /// the timeout period. This is a blocking operation.
  @override
  void waitForLocation(String path, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(
      () {
        final url = browser.getCurrentUrl();
        return Uri.parse(url).path == path;
      },
      timeout: timeout,
      operation: 'Wait for URL path "$path"',
    );
  }

  /// Waits for the page to reload after executing the synchronous [callback].
  ///
  /// Detects reload by comparing the page source before and after executing
  /// the callback. Uses polling with `sleep` and the [defaultTimeout].
  /// Throws a [TimeoutException] if the page source does not change within
  /// the timeout period. This is a blocking operation.
  @override
  void waitForReload(WaiterCallback callback) {
    final beforeSource = browser.getPageSource();
    callback();
    _waitUntil(
      () {
        final currentSource = browser.getPageSource();
        return currentSource != beforeSource;
      },
      timeout: defaultTimeout,
      operation: 'Wait for page reload',
    );
  }

  /// Internal helper method to wait until a synchronous [predicate] returns true,
  /// polling at a specified [interval] by sleeping the isolate.
  ///
  /// Throws a [TimeoutException] if the [predicate] does not return true
  /// within the given [timeout].
  void _waitUntil(
    bool Function() predicate, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 100),
    String? operation,
    String? selector,
  }) {
    final startTime = DateTime.now();
    final endTime = startTime.add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      if (predicate()) return;
      sleep(interval);
    }

    final elapsed = DateTime.now().difference(startTime);
    final message = _buildTimeoutMessage(operation, selector, timeout, elapsed);
    throw TimeoutException(-1, message);
  }

  /// Builds a descriptive timeout error message.
  String _buildTimeoutMessage(
    String? operation,
    String? selector,
    Duration timeout,
    Duration elapsed,
  ) {
    final buffer = StringBuffer();

    if (operation != null) {
      buffer.write('$operation failed: ');
    }

    buffer.write('Condition not met within ${timeout.inMilliseconds}ms');

    if (selector != null) {
      buffer.write(' for selector "$selector"');
    }

    buffer.write(' (elapsed: ${elapsed.inMilliseconds}ms)');

    return buffer.toString();
  }

  /// Pauses execution for the specified [timeout] duration by calling [sleep].
  ///
  /// This blocks the current isolate.
  @override
  FutureOr<void> wait(Duration timeout) {
    sleep(timeout);
  }

  // ========================================
  // Enhanced waiting methods
  // ========================================

  /// Waits for an element to appear in the DOM.
  ///
  /// This is an alias for [waitFor] with enhanced documentation.
  @override
  FutureOr<void> waitForElement(String selector, {Duration? timeout}) {
    waitFor(selector, timeout);
  }

  /// Waits for the browser to navigate to a specific URL.
  ///
  /// This is an alias for [waitForLocation] with enhanced documentation.
  @override
  FutureOr<void> waitForUrl(String url, {Duration? timeout}) {
    waitForLocation(url, timeout);
  }

  /// Pauses execution for the specified duration.
  ///
  /// This is an alias for [wait] with enhanced documentation.
  @override
  FutureOr<void> pause(Duration duration) {
    wait(duration);
  }
}
