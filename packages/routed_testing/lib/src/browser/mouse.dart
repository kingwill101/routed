import 'browser.dart';

class Mouse {
  final Browser browser;

  Mouse(this.browser);

  Future<Mouse> clickAndHold([String? selector]) async {
    if (selector != null) {
      final element = await browser.findElement(selector);
      await browser.driver.mouse.moveTo(element: element);
      await browser.driver.mouse.down();
    } else {
      await browser.driver.mouse.down();
    }
    return this;
  }

  Future<Mouse> releaseMouse() async {
    await browser.driver.mouse.up();
    return this;
  }

  Future<Mouse> moveTo(String selector) async {
    final element = await browser.findElement(selector);
    await browser.driver.mouse.moveTo(element: element);
    return this;
  }

  Future<Mouse> dragTo(String selector) async {
    final target = await browser.findElement(selector);
    await browser.driver.mouse.moveTo(element: target);
    return this;
  }

  Future<Mouse> dragOffset(int x, int y) async {
    await browser.driver.mouse.moveTo(xOffset: x, yOffset: y);
    return this;
  }

  Future<Mouse> moveToOffset(String selector,
      {int? xOffset, int? yOffset}) async {
    final element = await browser.findElement(selector);
    await browser.driver.mouse.moveTo(
      element: element,
      xOffset: xOffset,
      yOffset: yOffset,
    );
    return this;
  }
}
