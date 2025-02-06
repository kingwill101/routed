import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;
import '../interfaces/mouse.dart';
import 'browser.dart';

class SyncMouse implements Mouse {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncMouse(this.browser) : driver = browser.driver;

  @override
  Mouse clickAndHold([String? selector]) {
    if (selector != null) {
      final element = browser.findElement(selector);
      driver.mouse.moveTo(element: element);
      driver.mouse.down();
    } else {
      driver.mouse.down();
    }
    return this;
  }

  @override
  Mouse releaseMouse() {
    driver.mouse.up();
    return this;
  }

  @override
  Mouse moveTo(String selector) {
    final element = browser.findElement(selector);
    driver.mouse.moveTo(element: element);
    return this;
  }

  @override
  Mouse dragTo(String selector) {
    final target = browser.findElement(selector);
    driver.mouse.moveTo(element: target);
    return this;
  }

  @override
  Mouse dragOffset(int x, int y) {
    driver.mouse.moveTo(xOffset: x, yOffset: y);
    return this;
  }

  @override
  Mouse moveToOffset(String selector, {int? xOffset, int? yOffset}) {
    final element = browser.findElement(selector);
    driver.mouse.moveTo(
      element: element,
      xOffset: xOffset,
      yOffset: yOffset,
    );
    return this;
  }
}
