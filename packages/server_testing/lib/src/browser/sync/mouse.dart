// ignore_for_file: unused_shown_name

import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/mouse.dart';
import 'browser.dart';

/// Handles synchronous mouse interactions like clicking, dragging, and moving.
class SyncMouse implements Mouse {
  /// The parent [SyncBrowser] instance.
  final SyncBrowser browser;
  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;

  /// Creates a synchronous mouse handler for the given [browser].
  SyncMouse(this.browser) : driver = browser.driver;

  /// Moves the mouse to the element specified by [selector] (if provided)
  /// and holds the left mouse button down.
  ///
  /// If [selector] is null, performs the mouse down action at the current
  /// cursor position.
  /// Returns this [SyncMouse] instance for chaining. This is a blocking operation.
  @override
  Mouse clickAndHold([String? selector]) {
    if (selector != null) {
      final element = browser.findElement(selector);
      driver.mouse.moveTo(element: element);
      driver.mouse.down();
    } else {
      driver.mouse.down();
    }
    return this;
  }

  /// Releases the left mouse button.
  ///
  /// Returns this [SyncMouse] instance for chaining. This is a blocking operation.
  @override
  Mouse releaseMouse() {
    driver.mouse.up();
    return this;
  }

  /// Moves the mouse cursor to the center of the element specified by [selector].
  ///
  /// Returns this [SyncMouse] instance for chaining. This is a blocking operation.
  @override
  Mouse moveTo(String selector) {
    final element = browser.findElement(selector);
    driver.mouse.moveTo(element: element);
    return this;
  }

  /// Drags the mouse from its current position to the center of the element
  /// specified by [selector].
  ///
  /// Assumes the left mouse button is already held down (e.g., after [clickAndHold]).
  /// Returns this [SyncMouse] instance for chaining. This is a blocking operation.
  @override
  Mouse dragTo(String selector) {
    final target = browser.findElement(selector);
    driver.mouse.moveTo(element: target);
    return this;
  }

  /// Drags the mouse by the specified [x] and [y] offsets relative to its
  /// current position.
  ///
  /// Assumes the left mouse button is already held down.
  /// Returns this [SyncMouse] instance for chaining. This is a blocking operation.
  @override
  Mouse dragOffset(int x, int y) {
    driver.mouse.moveTo(xOffset: x, yOffset: y);
    return this;
  }

  /// Moves the mouse cursor to an offset relative to the top-left corner of
  /// the element specified by [selector].
  ///
  /// Specify the offset using [xOffset] and [yOffset]. If offsets are not
  /// provided, moves to the center of the element.
  /// Returns this [SyncMouse] instance for chaining. This is a blocking operation.
  @override
  Mouse moveToOffset(String selector, {int? xOffset, int? yOffset}) {
    final element = browser.findElement(selector);
    driver.mouse.moveTo(
      element: element,
      xOffset: xOffset,
      yOffset: yOffset,
    );
    return this;
  }
}
