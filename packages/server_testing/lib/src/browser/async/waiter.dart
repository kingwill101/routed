import 'dart:async';
import 'dart:io';

import '../interfaces/waiter.dart';
import 'browser.dart';

/// Provides asynchronous methods for waiting for specific conditions in the browser.
class AsyncBrowserWaiter implements BrowserWaiter {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The default timeout duration for wait operations if not specified explicitly.
  final Duration defaultTimeout;

  /// Creates an asynchronous waiter for the given [browser].
  ///
  /// Optionally sets a [defaultTimeout] to be used when no specific timeout
  /// is provided to the wait methods.
  AsyncBrowserWaiter(this.browser,
      [this.defaultTimeout = const Duration(seconds: 5)]);

  /// Waits for an element matching [selector] to be present in the DOM.
  ///
  /// Uses [defaultTimeout] if [timeout] is not provided. Throws a
  /// [TimeoutException] if the element is not found within the timeout period.
  @override
  Future<void> waitFor(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      return await browser.isPresent(selector);
    }, timeout: timeout);
  }

  /// Waits until no element matching [selector] is present in the DOM.
  ///
  /// Uses [defaultTimeout] if [timeout] is not provided. Throws a
  /// [TimeoutException] if the element still exists after the timeout period.
  @override
  Future<void> waitUntilMissing(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      return !(await browser.isPresent(selector));
    }, timeout: timeout);
  }

  /// Waits for the page source to contain the specified [text].
  ///
  /// Uses [defaultTimeout] if [timeout] is not provided. Throws a
  /// [TimeoutException] if the text is not found within the timeout period.
  @override
  Future<void> waitForText(String text, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      final source = await browser.getPageSource();
      return source.contains(text);
    }, timeout: timeout);
  }

  /// Waits for the current URL path to exactly match the specified [path].
  ///
  /// Uses [defaultTimeout] if [timeout] is not provided. Throws a
  /// [TimeoutException] if the path does not match within the timeout period.
  @override
  Future<void> waitForLocation(String path, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      final url = await browser.getCurrentUrl();
      return Uri.parse(url).path == path;
    }, timeout: timeout);
  }

  /// Waits for the page to reload after executing the asynchronous [callback].
  ///
  /// Detects reload by comparing the page source before and after executing
  /// the callback. Uses [defaultTimeout]. Throws a [TimeoutException] if the
  /// page source does not change within the timeout period.
  @override
  Future<void> waitForReload(WaiterCallback callback) async {
    final beforeSource = await browser.getPageSource();
    await callback();
    await _waitUntil(() async {
      final currentSource = await browser.getPageSource();
      return currentSource != beforeSource;
    }, timeout: defaultTimeout);
  }

  /// Internal helper method to wait until a [predicate] returns true, polling
  /// at a specified [interval].
  ///
  /// Throws a [TimeoutException] if the [predicate] does not return true
  /// within the given [timeout].
  Future<void> _waitUntil(
    Future<bool> Function() predicate, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      if (await predicate()) return;
      await Future<void>.delayed(interval);
    }
    throw TimeoutException('Condition not met within timeout', timeout);
  }

  /// Pauses execution for the specified [timeout] duration.
  ///
  /// Note: This uses [sleep], which blocks the current isolate. Prefer using
  /// other `waitFor*` methods that poll asynchronously when possible.
  @override
  Future<void> wait(Duration timeout) async {
    sleep(timeout);
  }
}
