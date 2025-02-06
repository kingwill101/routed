// ignore_for_file: unused_shown_name

import 'dart:io';

import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/keyboard.dart';
import 'browser.dart';

class SyncKeyboard implements Keyboard {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncKeyboard(this.browser) : driver = browser.driver;

  @override
  Keyboard type(List<String> keys) {
    for (final key in keys) {
      driver.keyboard.sendKeys(key);
    }
    return this;
  }

  @override
  Keyboard press(String key) {
    driver.keyboard.sendKeys(key);
    return this;
  }

  @override
  Keyboard release(String key) {
    // WebDriver automatically releases keys after sendKeys
    return this;
  }

  @override
  Keyboard sendModifier(String modifier, String key) {
    driver.keyboard.sendChord([modifier, key]);
    return this;
  }

  @override
  Keyboard pause([int milliseconds = 100]) {
    sleep(Duration(milliseconds: milliseconds));
    return this;
  }
}
