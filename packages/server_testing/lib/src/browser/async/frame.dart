import 'dart:async';

import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/frame.dart';
import 'browser.dart';

class AsyncFrameHandler implements FrameHandler {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncFrameHandler(this.browser) : driver = browser.driver;

  @override
  Future<void> withinFrame(String selector, Function(Browser) callback) async {
    final frame = await browser.findElement(selector);
    await driver.switchTo.frame(frame);
    try {
      await callback(browser);
    } finally {
      await driver.switchTo.frame(null);
    }
  }
}
