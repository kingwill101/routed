import 'dart:async';
import '../interfaces/waiter.dart';
import 'browser.dart';

class AsyncBrowserWaiter implements BrowserWaiter {
  final AsyncBrowser browser;
  final Duration defaultTimeout;

  AsyncBrowserWaiter(this.browser,
      [this.defaultTimeout = const Duration(seconds: 5)]);

  @override
  Future<void> waitFor(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      return await browser.isPresent(selector);
    }, timeout: timeout);
  }

  @override
  Future<void> waitUntilMissing(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      return !(await browser.isPresent(selector));
    }, timeout: timeout);
  }

  @override
  Future<void> waitForText(String text, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      final source = await browser.getPageSource();
      return source.contains(text);
    }, timeout: timeout);
  }

  @override
  Future<void> waitForLocation(String path, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(() async {
      final url = await browser.getCurrentUrl();
      return Uri.parse(url).path == path;
    }, timeout: timeout);
  }

  @override
  Future<void> waitForReload(Function() callback) async {
    final beforeSource = await browser.getPageSource();
    await callback();
    await _waitUntil(() async {
      final currentSource = await browser.getPageSource();
      return currentSource != beforeSource;
    }, timeout: defaultTimeout);
  }

  Future<void> _waitUntil(
    Future<bool> Function() predicate, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      if (await predicate()) return;
      await Future.delayed(interval);
    }
    throw TimeoutException('Condition not met within timeout', timeout);
  }
}
