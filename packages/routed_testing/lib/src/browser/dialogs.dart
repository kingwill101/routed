import 'browser.dart';

class DialogHandler {
  final Browser browser;

  DialogHandler(this.browser);

  Future<void> waitForDialog([Duration? timeout]) async {
    timeout ??= const Duration(seconds: 5);
    await browser.waitUntil(() async {
      try {
        browser.driver.switchTo.alert;
        return Future.value(true);
      } catch (_) {
        return Future.value(false);
      }
    }, timeout: timeout);
  }

  Future<void> acceptDialog() async {
    final alert = browser.driver.switchTo.alert;
    await alert.accept();
  }

  Future<void> dismissDialog() async {
    final alert = browser.driver.switchTo.alert;
    await alert.dismiss();
  }

  Future<void> typeInDialog(String text) async {
    final alert = browser.driver.switchTo.alert;
    await alert.sendKeys(text);
  }

  Future<void> assertDialogOpened(String message) async {
    final alert = browser.driver.switchTo.alert;
    final text = await alert.text;
    assert(text == message, 'Expected dialog with message: $message');
  }
}
