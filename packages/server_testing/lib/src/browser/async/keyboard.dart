import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/keyboard.dart';
import 'browser.dart';

class AsyncKeyboard implements Keyboard {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncKeyboard(this.browser) : driver = browser.driver;

  @override
  Future<Keyboard> type(List<String> keys) async {
    for (final key in keys) {
      await driver.keyboard.sendKeys(key);
    }
    return this;
  }

  @override
  Future<Keyboard> press(String key) async {
    await driver.keyboard.sendKeys(key);
    return this;
  }

  @override
  Future<Keyboard> release(String key) async {
    // WebDriver automatically releases keys after sendKeys
    return this;
  }

  @override
  Future<Keyboard> sendModifier(String modifier, String key) async {
    await driver.keyboard.sendChord([modifier, key]);
    return this;
  }

  @override
  Future<Keyboard> pause([int milliseconds = 100]) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return this;
  }
}
