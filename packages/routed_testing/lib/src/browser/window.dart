import 'dart:math';
import 'browser.dart';

class WindowManager {
  final Browser browser;

  WindowManager(this.browser);

  Future<void> resize(int width, int height) async {
    final window = await browser.driver.window;
    await window.setSize(Rectangle<int>(0, 0, width, height));
  }

  Future<void> maximize() async {
    final window = await browser.driver.window;
    await window.maximize();
  }

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

  Future<void> move(int x, int y) async {
    final window = await browser.driver.window;
    await window.setLocation(Point<int>(x, y));
  }
}
