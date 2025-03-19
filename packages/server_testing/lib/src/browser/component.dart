import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

abstract class Component {
  final Browser browser;
  final String selector;

  Component(this.browser, this.selector);

  Future<dynamic> findElement() async {
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
