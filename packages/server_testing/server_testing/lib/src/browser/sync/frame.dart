// ignore_for_file: unused_shown_name

import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/frame.dart';
import 'browser.dart';

/// Handles switching context to and from iframes synchronously.
class SyncFrameHandler implements FrameHandler {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;

  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous frame handler for the given [browser].
  SyncFrameHandler(this.browser) : driver = browser.driver;

  /// Executes the [callback] within the context of the iframe identified by [selector].
  ///
  /// Switches the WebDriver context to the specified iframe before executing the
  /// callback, and switches back to the main document context after the
  /// callback completes or throws an error. This is a blocking operation.
  @override
  void withinFrame(String selector, FrameCallback callback) {
    final frame = browser.findElement(selector);
    driver.switchTo.frame(frame);
    try {
      callback(browser);
    } finally {
      driver.switchTo.frame(null);
    }
  }
}
