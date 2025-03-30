import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/dialog.dart';
import 'browser.dart';

/// Handles asynchronous interactions with browser dialogs (alerts, confirms, prompts).
class AsyncDialogHandler implements DialogHandler {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous dialog handler for the given [browser].
  AsyncDialogHandler(this.browser) : driver = browser.driver;

  /// Waits for a browser dialog (alert, confirm, or prompt) to appear.
  ///
  /// Throws a [TimeoutException] if no dialog appears within the specified [timeout].
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

  /// Accepts the currently open dialog (e.g., clicks 'OK').
  ///
  @override
  Future<void> acceptDialog() async {
    final alert = driver.switchTo.alert;
    await alert.accept();
  }

  /// Dismisses the currently open dialog (e.g., clicks 'Cancel').
  ///
  @override
  Future<void> dismissDialog() async {
    final alert = driver.switchTo.alert;
    await alert.dismiss();
  }

  /// Types the specified [text] into the current prompt dialog.
  ///
  @override
  Future<void> typeInDialog(String text) async {
    final alert = driver.switchTo.alert;
    await alert.sendKeys(text);
  }

  /// Asserts that a dialog is open and contains the specified [message].
  ///
  @override
  Future<void> assertDialogOpened(String message) async {
    final alert = driver.switchTo.alert;
    final text = await alert.text;
    assert(text == message, 'Expected dialog with message: $message');
  }
}
