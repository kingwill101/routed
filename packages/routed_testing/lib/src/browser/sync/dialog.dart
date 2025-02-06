// ignore_for_file: unused_shown_name

import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/dialog.dart';
import 'browser.dart';

class SyncDialogHandler implements DialogHandler {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncDialogHandler(this.browser) : driver = browser.driver;

  @override
  void waitForDialog([Duration? timeout]) {
    timeout ??= const Duration(seconds: 5);
    browser.waitUntil(() {
      try {
        driver.switchTo.alert;
        return true;
      } catch (_) {
        return false;
      }
    }, timeout: timeout);
  }

  @override
  void acceptDialog() {
    final alert = driver.switchTo.alert;
    alert.accept();
  }

  @override
  void dismissDialog() {
    final alert = driver.switchTo.alert;
    alert.dismiss();
  }

  @override
  void typeInDialog(String text) {
    final alert = driver.switchTo.alert;
    alert.sendKeys(text);
  }

  @override
  void assertDialogOpened(String message) {
    final alert = driver.switchTo.alert;
    final text = alert.text;
    assert(text == message, 'Expected dialog with message: $message');
  }
}
