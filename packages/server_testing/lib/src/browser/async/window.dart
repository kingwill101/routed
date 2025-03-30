import 'dart:async';
import 'dart:math';

import 'package:webdriver/async_core.dart' show WebDriver;

import '../interfaces/window.dart';
import 'browser.dart';

/// Handles asynchronous management of the browser window's size and position.
class AsyncWindowManager implements WindowManager {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous window manager for the given [browser].
  AsyncWindowManager(this.browser) : driver = browser.driver;

  /// Resizes the browser window to the specified [width] and [height] in pixels.
  ///
  @override
  Future<void> resize(int width, int height) async {
    final window = await driver.window;
    await window.setSize(Rectangle<int>(0, 0, width, height));
  }

  /// Maximizes the browser window.
  ///
  @override
  Future<void> maximize() async {
    final window = await driver.window;
    await window.maximize();
  }

  /// Attempts to resize the browser window to fit the dimensions of the page content.
  ///
  /// Note: This relies on executing JavaScript to calculate content size and
  /// may not be perfectly accurate or supported by all WebDriver implementations.
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

  /// Moves the browser window to the specified screen coordinates ([x], [y]).
  ///
  /// The coordinates represent the desired position of the top-left corner
  /// of the window.
  @override
  Future<void> move(int x, int y) async {
    final window = await driver.window;
    await window.setLocation(Point<int>(x, y));
  }
}
