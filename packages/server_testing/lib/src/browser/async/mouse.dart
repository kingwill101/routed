// ignore_for_file: unused_shown_name

import 'dart:async';

import 'package:webdriver/async_core.dart' show WebDriver, WebElement;

import '../interfaces/mouse.dart';
import 'browser.dart';

/// Handles asynchronous mouse interactions like clicking, dragging, and moving.
class AsyncMouse implements Mouse {
  /// The parent [AsyncBrowser] instance.
  final AsyncBrowser browser;
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;

  /// Creates an asynchronous mouse handler for the given [browser].
  AsyncMouse(this.browser) : driver = browser.driver;

  /// Moves the mouse to the element specified by [selector] (if provided)
  /// and holds the left mouse button down.
  ///
  /// If [selector] is null, performs the mouse down action at the current
  /// cursor position.
  /// Returns this [AsyncMouse] instance for chaining.
  @override
  Future<Mouse> clickAndHold([String? selector]) async {
    if (selector != null) {
      final element = await browser.findElement(selector);
      await driver.mouse.moveTo(element: element as WebElement?);
      await driver.mouse.down();
    } else {
      await driver.mouse.down();
    }
    return this;
  }

  /// Releases the left mouse button.
  ///
  /// Returns this [AsyncMouse] instance for chaining.
  @override
  Future<Mouse> releaseMouse() async {
    await driver.mouse.up();
    return this;
  }

  /// Moves the mouse cursor to the center of the element specified by [selector].
  ///
  /// Returns this [AsyncMouse] instance for chaining.
  @override
  Future<Mouse> moveTo(String selector) async {
    final element = await browser.findElement(selector);
    await driver.mouse.moveTo(element: element as WebElement?);
    return this;
  }

  /// Drags the mouse from its current position to the center of the element
  /// specified by [selector].
  ///
  /// Assumes the left mouse button is already held down (e.g., after [clickAndHold]).
  /// Returns this [AsyncMouse] instance for chaining.
  @override
  Future<Mouse> dragTo(String selector) async {
    final target = await browser.findElement(selector);
    await driver.mouse.moveTo(element: target as WebElement?);
    return this;
  }

  /// Drags the mouse by the specified [x] and [y] offsets relative to its
  /// current position.
  ///
  /// Assumes the left mouse button is already held down.
  /// Returns this [AsyncMouse] instance for chaining.
  @override
  Future<Mouse> dragOffset(int x, int y) async {
    await driver.mouse.moveTo(xOffset: x, yOffset: y);
    return this;
  }

  /// Moves the mouse cursor to an offset relative to the top-left corner of
  /// the element specified by [selector].
  ///
  /// Specify the offset using [xOffset] and [yOffset]. If offsets are not
  /// provided, moves to the center of the element.
  /// Returns this [AsyncMouse] instance for chaining.
  @override
  Future<Mouse> moveToOffset(String selector,
      {int? xOffset, int? yOffset}) async {
    final element = await browser.findElement(selector);
    await driver.mouse.moveTo(
      element: element as WebElement?,
      xOffset: xOffset,
      yOffset: yOffset,
    );
    return this;
  }
}
