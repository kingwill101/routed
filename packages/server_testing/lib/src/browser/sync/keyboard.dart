// ignore_for_file: unused_shown_name

import 'dart:io';

import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/keyboard.dart';
import 'browser.dart';

/// Handles synchronous keyboard input simulation.
class SyncKeyboard implements Keyboard {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;
  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous keyboard handler for the given [browser].
  SyncKeyboard(this.browser) : driver = browser.driver;

  /// Types a sequence of [keys] into the currently focused element.
  ///
  /// Returns this [SyncKeyboard] instance for chaining. This is a blocking operation.
  @override
  Keyboard type(List<String> keys) {
    for (final key in keys) {
      driver.keyboard.sendKeys(key);
    }
    return this;
  }

  /// Simulates pressing and releasing a single [key].
  ///
  /// Returns this [SyncKeyboard] instance for chaining. This is a blocking operation.
  @override
  Keyboard press(String key) {
    driver.keyboard.sendKeys(key);
    return this;
  }

  /// Simulates releasing a specific [key].
  ///
  /// Note: WebDriver's `sendKeys` typically handles key release automatically,
  /// so this method might be a no-op. Provided for completeness.
  /// Returns this [SyncKeyboard] instance for chaining. This is a blocking operation.
  @override
  Keyboard release(String key) {
    // WebDriver automatically releases keys after sendKeys
    return this;
  }

  /// Sends a [key] press while holding down a [modifier] key (e.g., Ctrl, Shift, Alt).
  ///
  /// Returns this [SyncKeyboard] instance for chaining. This is a blocking operation.
  @override
  Keyboard sendModifier(String modifier, String key) {
    driver.keyboard.sendChord([modifier, key]);
    return this;
  }

  /// Pauses keyboard actions for the specified duration in [milliseconds].
  ///
  /// Uses [sleep], which blocks the current isolate.
  /// Returns this [SyncKeyboard] instance for chaining.
  @override
  Keyboard pause([int milliseconds = 100]) {
    sleep(Duration(milliseconds: milliseconds));
    return this;
  }
}
