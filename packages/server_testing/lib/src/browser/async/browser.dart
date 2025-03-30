import 'dart:async';

import 'package:server_testing/src/browser/async/assertions.dart';
import 'package:server_testing/src/browser/async/cookie.dart';
import 'package:server_testing/src/browser/async/dialog.dart';
import 'package:server_testing/src/browser/async/frame.dart';
import 'package:server_testing/src/browser/async/keyboard.dart';
import 'package:server_testing/src/browser/async/local_storage.dart';
import 'package:server_testing/src/browser/async/mouse.dart';
import 'package:server_testing/src/browser/async/session_storage.dart';
import 'package:server_testing/src/browser/async/waiter.dart';
import 'package:server_testing/src/browser/async/window.dart';
import 'package:server_testing/src/browser/browser_config.dart';
import 'package:server_testing/src/browser/interfaces/download.dart';
import 'package:server_testing/src/browser/interfaces/emulation.dart';
import 'package:server_testing/src/browser/interfaces/network.dart';
import 'package:server_testing/src/browser/utils.dart';
import 'package:webdriver/async_core.dart' show WebDriver, By;

import '../interfaces/browser.dart';

/// An asynchronous implementation of the [Browser] interface using `package:webdriver`'s async API.
///
/// Provides methods for controlling a browser and interacting with web pages
/// using non-blocking operations.
class AsyncBrowser with AsyncBrowserAssertions implements Browser {
  /// The underlying asynchronous WebDriver instance.
  final WebDriver driver;
  /// The configuration for this browser instance.
  final BrowserConfig config;

  /// Handler for asynchronous keyboard interactions.
  @override
  late final keyboard = AsyncKeyboard(this);

  /// Handler for asynchronous mouse interactions.
  @override
  late final mouse = AsyncMouse(this);

  /// Handler for asynchronous dialog interactions.
  @override
  late final dialogs = AsyncDialogHandler(this);

  /// Handler for asynchronous frame interactions.
  @override
  late final frames = AsyncFrameHandler(this);

  /// Handler for asynchronous waiting operations.
  @override
  late final waiter = AsyncBrowserWaiter(this);

  /// Handler for asynchronous window management.
  @override
  late final window = AsyncWindowManager(this);

  /// Handler for asynchronous cookie management.
  @override
  late final cookies = AsyncCookieHandler(this);

  /// Handler for asynchronous local storage access.
  @override
  late final localStorage = AsyncLocalStorageHandler(this);

  /// Handler for asynchronous session storage access.
  @override
  late final sessionStorage = AsyncSessionStorageHandler(this);

  /// Creates an instance of [AsyncBrowser].
  AsyncBrowser(this.driver, this.config);

  /// Navigates the browser to the specified [url].
  ///
  /// Resolves relative URLs against the [config.baseUrl].
  @override
  Future<void> visit(String url) => driver.get(resolveUrl(url, config: config));

  /// Navigates back in the browser's history.
  @override
  Future<void> back() => driver.back();

  /// Navigates forward in the browser's history.
  @override
  Future<void> forward() => driver.forward();

  /// Refreshes the current page.
  @override
  Future<void> refresh() => driver.refresh();

  /// Clicks the element identified by [selector].
  ///
  /// Throws an exception if the element is not found.
  @override
  Future<void> click(String selector) async {
    final element = await findElement(selector);
    await element.click();
  }

  /// Types the given [value] into the element identified by [selector].
  ///
  /// Clears the element before typing. Throws an exception if the element is not found.
  @override
  Future<void> type(String selector, String value) async {
    final element = await findElement(selector);
    await element.clear();
    await element.sendKeys(value);
  }

  /// Finds the first element matching the CSS [selector].
  ///
  /// Supports standard CSS selectors. If [selector] starts with `@`, finds
  /// elements with a matching `dusk` attribute (e.g., `@my-component`).
  /// Throws an exception if no element is found.
  @override
  Future<dynamic> findElement(String selector) async {
    try {
      if (selector.startsWith('@')) {
        return await driver
            .findElement(By.cssSelector('[dusk="${selector.substring(1)}"]'));
      }
      return await driver.findElement(By.cssSelector(selector));
    } catch (e) {
      throw Exception('Could not find element: $selector');
    }
  }

  /// Checks if an element matching [selector] is present in the DOM.
  @override
  Future<bool> isPresent(String selector) async {
    try {
      await findElement(selector);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gets the HTML source of the current page.
  @override
  Future<String> getPageSource() => driver.pageSource;

  /// Gets the current URL of the browser.
  @override
  Future<String> getCurrentUrl() => driver.currentUrl;

  /// Gets the title of the current page.
  @override
  Future<String> getTitle() => driver.title;

  /// Executes the given JavaScript [script] in the context of the current page.
  ///
  /// Returns the value returned by the script.
  @override
  Future<dynamic> executeScript(String script) => driver.execute(script, []);

  /// Waits until the [predicate] function returns true.
  ///
  /// Checks the predicate periodically using [interval] until [timeout] is reached.
  /// Throws a [TimeoutException] if the condition is not met within the timeout period.
  @override
  Future<void> waitUntil(
    FutureOr<bool> Function() predicate, {
    Duration? timeout,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    timeout ??= const Duration(seconds: 5);
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      if (await predicate()) return;
      await Future<void>.delayed(interval);
    }

    throw TimeoutException('Condition not met within timeout', timeout);
  }

  /// Closes the browser and terminates the WebDriver session.
  @override
  Future<void> quit() => driver.quit();

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
