import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/frame.dart';
import 'browser.dart';

/// Handles switching context to and from iframes asynchronously.
class AsyncFrameHandler implements FrameHandler {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous frame handler for the given [browser].
  AsyncFrameHandler(this.browser) : driver = browser.driver;

  /// Executes the [callback] within the context of the iframe identified by [selector].
  ///
  /// Switches the WebDriver context to the specified iframe before executing the
  /// callback, and switches back to the main document context after the
  /// callback completes or throws an error.
  @override
  Future<void> withinFrame(String selector, FrameCallback callback) async {
    final frame = await browser.findElement(selector);
    await driver.switchTo.frame(frame);
    try {
      await callback(browser);
    } finally {
      await driver.switchTo.frame(null);
    }
  }
}
