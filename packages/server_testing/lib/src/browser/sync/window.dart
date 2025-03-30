import 'dart:math';

import 'package:webdriver/sync_core.dart' show WebDriver;

import '../interfaces/window.dart';
import 'browser.dart';

/// Handles synchronous management of the browser window's size and position.
class SyncWindowManager implements WindowManager {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;
  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous window manager for the given [browser].
  SyncWindowManager(this.browser) : driver = browser.driver;

  /// Resizes the browser window to the specified [width] and [height] in pixels.
  /// This is a blocking operation.
  @override
  void resize(int width, int height) {
    final window = driver.window;
    window.setSize(Rectangle<int>(0, 0, width, height));
  }

  /// Maximizes the browser window. This is a blocking operation.
  @override
  void maximize() {
    driver.window.maximize();
  }

  /// Attempts to resize the browser window to fit the dimensions of the page content.
  ///
  /// Note: Relies on executing JavaScript and may not be perfectly accurate or
  /// supported by all WebDriver implementations. This is a blocking operation.
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

  /// Moves the browser window to the specified screen coordinates ([x], [y]).
  ///
  /// Coordinates represent the desired position of the top-left corner.
  /// This is a blocking operation.
  @override
  void move(int x, int y) {
    final window = driver.window;
    window.setLocation(Point<int>(x, y));
  }
}
