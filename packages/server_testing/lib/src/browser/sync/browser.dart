import 'dart:async' show FutureOr, TimeoutException;
import 'dart:io' show sleep;

import 'package:server_testing/src/browser/browser_config.dart';
import 'package:server_testing/src/browser/interfaces/download.dart';
import 'package:server_testing/src/browser/interfaces/emulation.dart';
import 'package:server_testing/src/browser/interfaces/network.dart';
import 'package:server_testing/src/browser/sync/assertions.dart';
import 'package:server_testing/src/browser/sync/cookie.dart';
import 'package:server_testing/src/browser/sync/local_storage.dart';
import 'package:server_testing/src/browser/sync/session_storage.dart';
import 'package:server_testing/src/browser/utils.dart';
import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/browser.dart';
import 'dialog.dart';
import 'frame.dart';
import 'keyboard.dart';
import 'mouse.dart';
import 'waiter.dart';
import 'window.dart';

/// A synchronous implementation of the [Browser] interface using `package:webdriver`'s sync API.
///
/// Provides methods for controlling a browser and interacting with web pages
/// using blocking operations. Most methods return `void` or a direct result,
/// unlike the `Future`-based methods in [AsyncBrowser].
class SyncBrowser with SyncBrowserAssertions implements Browser {
  /// The underlying synchronous WebDriver instance.
  final WebDriver driver;
  /// The configuration for this browser instance.
  final BrowserConfig config;

  /// Handler for synchronous keyboard interactions.
  @override
  late final keyboard = SyncKeyboard(this);
  /// Handler for synchronous mouse interactions.
  @override
  late final mouse = SyncMouse(this);
  /// Handler for synchronous dialog interactions.
  @override
  late final dialogs = SyncDialogHandler(this);
  /// Handler for synchronous frame interactions.
  @override
  late final frames = SyncFrameHandler(this);
  /// Handler for synchronous waiting operations.
  @override
  late final waiter = SyncBrowserWaiter(this);
  /// Handler for synchronous window management.
  @override
  late final window = SyncWindowManager(this);
  /// Handler for synchronous cookie management.
  @override
  late final cookies = SyncCookieHandler(this);
  /// Handler for synchronous local storage access.
  @override
  late final localStorage = SyncLocalStorageHandler(this);
  /// Handler for synchronous session storage access.
  @override
  late final sessionStorage = SyncSessionStorageHandler(this);

  /// Creates an instance of [SyncBrowser].
  SyncBrowser(this.driver, this.config);

  /// Waits until the [predicate] function returns true.
  ///
  /// Checks the predicate periodically using [interval] (by sleeping the isolate)
  /// until [timeout] is reached.
  /// Throws a [TimeoutException] if the condition is not met within the timeout period.
  ///
  /// Note: This uses `sleep`, which blocks the current isolate. Use with caution.
  @override
  FutureOr<void> waitUntil(
    FutureOr<bool> Function() predicate, {
    Duration? timeout,
    Duration interval = const Duration(milliseconds: 100),
  }) {
    timeout ??= const Duration(seconds: 5);
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      if (predicate() as bool) return null;
      sleep(interval);
    }

    throw TimeoutException('Condition not met within timeout', timeout);
  }

  /// Navigates the browser to the specified [url].
  ///
  /// Resolves relative URLs against the [config.baseUrl]. This is a blocking operation.
  @override
  void visit(String url) => driver.get(resolveUrl(url, config: config));

  /// Navigates back in the browser's history. This is a blocking operation.
  @override
  void back() => driver.back();

  /// Navigates forward in the browser's history. This is a blocking operation.
  @override
  void forward() => driver.forward();

  /// Refreshes the current page. This is a blocking operation.
  @override
  void refresh() => driver.refresh();

  /// Clicks the element identified by [selector].
  ///
  /// Throws an exception if the element is not found. This is a blocking operation.
  @override
  void click(String selector) {
    final element = findElement(selector);
    element.click();
  }

  /// Types the given [value] into the element identified by [selector].
  ///
  /// Clears the element before typing. Throws an exception if the element is not found.
  /// This is a blocking operation.
  @override
  void type(String selector, String value) {
    final element = findElement(selector);
    element.clear();
    element.sendKeys(value);
  }

  /// Finds the first element matching the CSS [selector].
  ///
  /// Supports standard CSS selectors. If [selector] starts with `@`, finds
  /// elements with a matching `dusk` attribute (e.g., `@my-component`).
  /// Throws an exception if no element is found. This is a blocking operation.
  @override
  WebElement findElement(String selector) {
    try {
      if (selector.startsWith('@')) {
        return driver
            .findElement(By.cssSelector('[dusk="${selector.substring(1)}"]'));
      }
      return driver.findElement(By.cssSelector(selector));
    } catch (e) {
      throw Exception('Could not find element: $selector');
    }
  }

  /// Checks if an element matching [selector] is present in the DOM.
  ///
  /// This is a blocking operation.
  @override
  bool isPresent(String selector) {
    try {
      findElement(selector);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gets the HTML source of the current page. This is a blocking operation.
  @override
  String getPageSource() => driver.pageSource;

  /// Gets the current URL of the browser. This is a blocking operation.
  @override
  String getCurrentUrl() => driver.currentUrl;

  /// Gets the title of the current page. This is a blocking operation.
  @override
  String getTitle() => driver.title;

  /// Executes the given JavaScript [script] in the context of the current page.
  ///
  /// Returns the value returned by the script. This is a blocking operation.
  @override
  dynamic executeScript(String script) => driver.execute(script, []);

  /// Closes the browser and terminates the WebDriver session. This is a blocking operation.
  @override
  void quit() => driver.quit();

  @override
  
  /// Handler for file download operations. (Not yet implemented)
  Download get download => throw UnimplementedError();

  @override
  
  /// Handler for device emulation. (Not yet implemented)
  Emulation get emulation => throw UnimplementedError();

  @override
  
  /// Handler for network request interception. (Not yet implemented)
  Network get network => throw UnimplementedError();
}
