import 'dart:io' show sleep;
import 'package:webdriver/sync_core.dart'
    show By, TimeoutException, WebDriver, WebElement;
import '../interfaces/waiter.dart';
import 'browser.dart';

class SyncBrowserWaiter implements BrowserWaiter {
  final SyncBrowser browser;
  final Duration defaultTimeout;

  SyncBrowserWaiter(this.browser,
      [this.defaultTimeout = const Duration(seconds: 5)]);

  @override
  void waitFor(String selector, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(() => browser.isPresent(selector), timeout: timeout);
  }

  @override
  void waitUntilMissing(String selector, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(() => !browser.isPresent(selector), timeout: timeout);
  }

  @override
  void waitForText(String text, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(() {
      final source = browser.getPageSource();
      return source.contains(text);
    }, timeout: timeout);
  }

  @override
  void waitForLocation(String path, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(() {
      final url = browser.getCurrentUrl();
      return Uri.parse(url).path == path;
    }, timeout: timeout);
  }

  @override
  void waitForReload(Function() callback) {
    final beforeSource = browser.getPageSource();
    callback();
    _waitUntil(() {
      final currentSource = browser.getPageSource();
      return currentSource != beforeSource;
    }, timeout: defaultTimeout);
  }

  void _waitUntil(
    bool Function() predicate, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 100),
  }) {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      if (predicate()) return;
      sleep(interval);
    }
    throw TimeoutException(-1, 'Condition not met within timeout $timeout');
  }
}
