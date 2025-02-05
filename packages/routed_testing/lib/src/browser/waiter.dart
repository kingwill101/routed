import 'dart:async';
import 'package:test/test.dart';
import 'browser.dart';

class BrowserWaiter {
  final Browser browser;
  final Duration defaultTimeout;

  BrowserWaiter(this.browser,
      [this.defaultTimeout = const Duration(seconds: 5)]);

  Future<void> waitFor(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    try {
      await _waitUntil(() async {
        return await browser.isPresent(selector);
      }, timeout: timeout);
    } on TimeoutException {
      throw TestFailure('Timed out waiting for selector: $selector');
    }
  }

  Future<void> waitUntilMissing(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    try {
      await _waitUntil(() async {
        return !(await browser.isPresent(selector));
      }, timeout: timeout);
    } on TimeoutException {
      throw TestFailure(
          'Timed out waiting for selector to disappear: $selector');
    }
  }

  Future<void> waitForText(String text, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    try {
      await _waitUntil(() async {
        final source = await browser.getPageSource();
        return source.contains(text);
      }, timeout: timeout);
    } on TimeoutException {
      throw TestFailure('Timed out waiting for text: $text');
    }
  }

  Future<void> waitForLocation(String path, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    try {
      await _waitUntil(() async {
        final currentUrl = await browser.getCurrentUrl();
        return Uri.parse(currentUrl).path == path;
      }, timeout: timeout);
    } on TimeoutException {
      throw TestFailure('Timed out waiting for location: $path');
    }
  }

  Future<void> waitForReload(Future<void> Function() callback) async {
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
      if (await predicate()) {
        return;
      }
      await Future.delayed(interval);
    }

    throw TimeoutException('Condition not met within timeout', timeout);
  }
}
