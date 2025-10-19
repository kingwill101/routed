import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/keyboard.dart';
import 'browser.dart';

/// Handles asynchronous keyboard input simulation.
class AsyncKeyboard implements Keyboard {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;

  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous keyboard handler for the given [browser].
  AsyncKeyboard(this.browser) : driver = browser.driver;

  /// Types a sequence of [keys] into the currently focused element.
  ///
  /// Returns this [AsyncKeyboard] instance for chaining.
  @override
  Future<Keyboard> type(List<String> keys) async {
    for (final key in keys) {
      await driver.keyboard.sendKeys(key);
    }
    return this;
  }

  /// Simulates pressing and releasing a single [key].
  ///
  /// Returns this [AsyncKeyboard] instance for chaining.
  @override
  Future<Keyboard> press(String key) async {
    await driver.keyboard.sendKeys(key);
    return this;
  }

  /// Simulates releasing a specific [key].
  ///
  /// Note: WebDriver's `sendKeys` typically handles key release automatically,
  /// so this method might be a no-op depending on the specific driver behavior.
  /// It's provided for completeness but may not be necessary in most cases.
  /// Returns this [AsyncKeyboard] instance for chaining.
  @override
  Future<Keyboard> release(String key) async {
    // WebDriver automatically releases keys after sendKeys
    return this;
  }

  /// Sends a [key] press while holding down a [modifier] key (e.g., Ctrl, Shift, Alt).
  ///
  /// Returns this [AsyncKeyboard] instance for chaining.
  @override
  Future<Keyboard> sendModifier(String modifier, String key) async {
    await driver.keyboard.sendChord([modifier, key]);
    return this;
  }

  /// Pauses keyboard actions for the specified duration in [milliseconds].
  ///
  /// Returns this [AsyncKeyboard] instance for chaining.
  @override
  Future<Keyboard> pause([int milliseconds = 100]) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return this;
  }
}
