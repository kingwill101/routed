import 'dart:math';

import 'package:webdriver/sync_core.dart'
    show WebDriver;
import '../interfaces/window.dart';
import 'browser.dart';

class SyncWindowManager implements WindowManager {
  final SyncBrowser browser;
  final WebDriver driver;

  SyncWindowManager(this.browser) : driver = browser.driver;

  @override
  void resize(int width, int height) {
    final window = driver.window;
    window.setSize(Rectangle<int>(0, 0, width, height));
  }

  @override
  void maximize() {
    driver.window.maximize();
  }

  @override
  void fitContent() {
    browser.executeScript('''
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
  void move(int x, int y) {
    final window = driver.window;
    window.setLocation(Point<int>(x, y));
  }
}
