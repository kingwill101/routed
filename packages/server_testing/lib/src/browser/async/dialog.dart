import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/dialog.dart';
import 'browser.dart';

class AsyncDialogHandler implements DialogHandler {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncDialogHandler(this.browser) : driver = browser.driver;

  @override
  Future<void> waitForDialog([Duration? timeout]) async {
    timeout ??= const Duration(seconds: 5);
    await browser.waitUntil(() async {
      try {
        driver.switchTo.alert;
        return true;
      } catch (_) {
        return false;
      }
    }, timeout: timeout);
  }

  @override
  Future<void> acceptDialog() async {
    final alert = driver.switchTo.alert;
    await alert.accept();
  }

  @override
  Future<void> dismissDialog() async {
    final alert = driver.switchTo.alert;
    await alert.dismiss();
  }

  @override
  Future<void> typeInDialog(String text) async {
    final alert = driver.switchTo.alert;
    await alert.sendKeys(text);
  }

  @override
  Future<void> assertDialogOpened(String message) async {
    final alert = driver.switchTo.alert;
    final text = await alert.text;
    assert(text == message, 'Expected dialog with message: $message');
  }
}
