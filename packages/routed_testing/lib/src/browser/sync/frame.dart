import 'package:routed_testing/src/browser/interfaces/browser.dart';
import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;
import '../interfaces/frame.dart';
import 'browser.dart';

class SyncFrameHandler implements FrameHandler {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncFrameHandler(this.browser) : driver = browser.driver;

  @override
  void withinFrame(String selector, Function(Browser) callback) {
    final frame = browser.findElement(selector);
    driver.switchTo.frame(frame);
    try {
      callback(browser);
    } finally {
      driver.switchTo.frame(null);
    }
  }
}
