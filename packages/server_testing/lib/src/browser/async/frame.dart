import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/frame.dart';
import 'browser.dart';

class AsyncFrameHandler implements FrameHandler {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncFrameHandler(this.browser) : driver = browser.driver;

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
