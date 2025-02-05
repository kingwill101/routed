import 'browser.dart';

class FrameHandler {
  final Browser browser;

  FrameHandler(this.browser);

  Future<void> withinFrame(String selector, Function(Browser) callback) async {
    final frame = await browser.findElement(selector);
    await browser.driver.switchTo.frame(frame);

    try {
      await callback(browser);
    } finally {
      // Switch back to the default content/main frame
      await browser.driver.switchTo.frame(null);
    }
  }
}
