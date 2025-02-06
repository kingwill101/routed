import 'dart:async';
import 'dart:math';
import 'package:webdriver/async_core.dart' show WebDriver, WebElement, By, Rectangle;
import '../interfaces/window.dart';
import 'browser.dart';

class AsyncWindowManager implements WindowManager {
  final AsyncBrowser browser;
  final WebDriver driver;

  AsyncWindowManager(this.browser) : driver = browser.driver;

  @override
  Future<void> resize(int width, int height) async {
    final window = await driver.window;
    await window.setSize(Rectangle<int>(0, 0, width, height));
  }

  @override
  Future<void> maximize() async {
    final window = await driver.window;
    await window.maximize();
  }

  @override
  Future<void> fitContent() async {
    await browser.executeScript('''
      const body = document.body;
      const html = document.documentElement;
      const height = Math.max(
        body.scrollHeight, body.offsetHeight,
        html.clientHeight, html.scrollHeight, html.offsetHeight
      );
      const width = Math.max(
        body.scrollWidth, body.offsetWidth,
        html.clientWidth, html.scrollWidth, html.offsetWidth
      );
      window.resizeTo(width, height);
    ''');
  }

  @override
  Future<void> move(int x, int y) async {
    final window = await driver.window;
    await window.setLocation(Point<int>(x, y));
  }
}
