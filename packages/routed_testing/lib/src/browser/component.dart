import 'package:test/test.dart';
import 'package:webdriver/async_core.dart' show WebElement;
import 'browser.dart';

abstract class Component {
  final Browser browser;
  final String selector;

  Component(this.browser, this.selector);

  Future<WebElement> findElement() async {
    return await browser.findElement(selector);
  }

  Future<void> assertVisible() async {
    final element = await findElement();
    if (!await element.displayed) {
      throw TestFailure('Component is not visible');
    }
  }

  Future<void> assertHidden() async {
    final element = await findElement();
    if (await element.displayed) {
      throw TestFailure('Component is visible');
    }
  }
}
