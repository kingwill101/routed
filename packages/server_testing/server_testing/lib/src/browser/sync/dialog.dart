// ignore_for_file: unused_shown_name

import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/dialog.dart';
import 'browser.dart';

/// Handles synchronous interactions with browser dialogs (alerts, confirms, prompts).
class SyncDialogHandler implements DialogHandler {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;

  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous dialog handler for the given [browser].
  SyncDialogHandler(this.browser) : driver = browser.driver;

  /// Waits for a browser dialog (alert, confirm, or prompt) to appear.
  ///
  /// Uses polling with `sleep`. Throws a [TimeoutException] if no dialog
  /// appears within the specified [timeout]. This is a blocking operation.
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

  /// Accepts the currently open dialog (e.g., clicks 'OK').
  /// This is a blocking operation.
  @override
  void acceptDialog() {
    final alert = driver.switchTo.alert;
    alert.accept();
  }

  /// Dismisses the currently open dialog (e.g., clicks 'Cancel').
  /// This is a blocking operation.
  @override
  void dismissDialog() {
    final alert = driver.switchTo.alert;
    alert.dismiss();
  }

  /// Types the specified [text] into the current prompt dialog.
  /// This is a blocking operation.
  @override
  void typeInDialog(String text) {
    final alert = driver.switchTo.alert;
    alert.sendKeys(text);
  }

  /// Asserts that a dialog is open and contains the specified [message].
  /// This is a blocking operation.
  @override
  void assertDialogOpened(String message) {
    final alert = driver.switchTo.alert;
    final text = alert.text;
    assert(text == message, 'Expected dialog with message: $message');
  }
}
