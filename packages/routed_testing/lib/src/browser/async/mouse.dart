// ignore_for_file: unused_shown_name

import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver, WebElement;

import '../interfaces/mouse.dart';
import 'browser.dart';

class AsyncMouse implements Mouse {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncMouse(this.browser) : driver = browser.driver;

  @override
  Future<Mouse> clickAndHold([String? selector]) async {
    if (selector != null) {
      final element = await browser.findElement(selector);
      await driver.mouse.moveTo(element: element);
      await driver.mouse.down();
    } else {
      await driver.mouse.down();
    }
    return this;
  }

  @override
  Future<Mouse> releaseMouse() async {
    await driver.mouse.up();
    return this;
  }

  @override
  Future<Mouse> moveTo(String selector) async {
    final element = await browser.findElement(selector);
    await driver.mouse.moveTo(element: element);
    return this;
  }

  @override
  Future<Mouse> dragTo(String selector) async {
    final target = await browser.findElement(selector);
    await driver.mouse.moveTo(element: target);
    return this;
  }

  @override
  Future<Mouse> dragOffset(int x, int y) async {
    await driver.mouse.moveTo(xOffset: x, yOffset: y);
    return this;
  }

  @override
  Future<Mouse> moveToOffset(String selector,
      {int? xOffset, int? yOffset}) async {
    final element = await browser.findElement(selector);
    await driver.mouse.moveTo(
      element: element,
      xOffset: xOffset,
      yOffset: yOffset,
    );
    return this;
  }
}
