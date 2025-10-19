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
import 'package:server_testing/src/browser/browser_logger.dart'
    show EnhancedBrowserLogger;
import 'package:server_testing/src/browser/enhanced_exceptions.dart';
import 'package:server_testing/src/browser/interfaces/download.dart';
import 'package:server_testing/src/browser/interfaces/emulation.dart';
import 'package:server_testing/src/browser/interfaces/network.dart';
import 'package:server_testing/src/browser/screenshot_manager.dart';
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

  /// Logger for browser operations and debugging.
  late final EnhancedBrowserLogger _logger = EnhancedBrowserLogger(
    verboseLogging: config.verboseLogging,
    logDirectory: config.logDir,
  );

  /// Manager for screenshot capture and automatic failure screenshots.
  late final ScreenshotManager _screenshotManager = ScreenshotManager(
    screenshotDirectory: config.screenshotDirectory,
    autoScreenshots: config.autoScreenshots,
  );

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
    _logger.logOperationStart('click', selector: selector);
    final startTime = DateTime.now();

    try {
      final element = await findElement(selector);
      await element.click();

      final duration = DateTime.now().difference(startTime);
      _logger.logOperationComplete(
        'click',
        selector: selector,
        duration: duration,
      );
    } catch (e) {
      final screenshotPath = await _screenshotManager.captureFailureScreenshot(
        driver,
        action: 'click',
        selector: selector,
      );

      _logger.logError(
        'Failed to click element',
        action: 'click',
        selector: selector,
        error: e,
      );

      throw EnhancedBrowserException(
        'Failed to click element: $selector',
        selector: selector,
        action: 'click',
        screenshotPath: screenshotPath,
        cause: e,
      );
    }
  }

  /// Types the given [value] into the element identified by [selector].
  ///
  /// Clears the element before typing. Throws an exception if the element is not found.
  @override
  Future<void> type(String selector, String value) async {
    _logger.logOperationStart(
      'type',
      selector: selector,
      parameters: {'value': value},
    );
    final startTime = DateTime.now();

    try {
      final element = await findElement(selector);
      await element.clear();
      await element.sendKeys(value);

      final duration = DateTime.now().difference(startTime);
      _logger.logOperationComplete(
        'type',
        selector: selector,
        duration: duration,
      );
    } catch (e) {
      final screenshotPath = await _screenshotManager.captureFailureScreenshot(
        driver,
        action: 'type',
        selector: selector,
      );

      _logger.logError(
        'Failed to type into element',
        action: 'type',
        selector: selector,
        details: 'Attempted to type: "$value"',
        error: e,
      );

      throw EnhancedBrowserException(
        'Failed to type into element: $selector',
        selector: selector,
        action: 'type',
        screenshotPath: screenshotPath,
        details: 'Attempted to type: "$value"',
        cause: e,
      );
    }
  }

  /// Finds the first element matching the CSS [selector].
  ///
  /// Supports standard CSS selectors. If [selector] starts with `@`, finds
  /// elements with a matching `dusk` attribute (e.g., `@my-component`).
  /// Throws an exception if no element is found.
  @override
  Future<dynamic> findElement(String selector) async {
    _logger.logInfo('Finding element', selector: selector);

    try {
      if (selector.startsWith('@')) {
        final duskSelector = '[dusk="${selector.substring(1)}"]';
        _logger.logInfo('Using dusk selector', selector: duskSelector);
        return await driver.findElement(By.cssSelector(duskSelector));
      }
      return await driver.findElement(By.cssSelector(selector));
    } catch (e) {
      final screenshotPath = await _screenshotManager.captureFailureScreenshot(
        driver,
        action: 'findElement',
        selector: selector,
      );

      _logger.logError(
        'Element not found',
        action: 'findElement',
        selector: selector,
        error: e,
      );

      throw EnhancedBrowserException(
        'Could not find element: $selector',
        selector: selector,
        action: 'findElement',
        screenshotPath: screenshotPath,
        cause: e,
      );
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

  // ========================================
  // Laravel Dusk-inspired convenience methods
  // ========================================

  /// Clicks on a link containing the specified text.
  @override
  Future<void> clickLink(String linkText) async {
    final element = await driver.findElement(By.partialLinkText(linkText));
    await element.click();
  }

  /// Selects an option from a dropdown/select element.
  @override
  Future<void> selectOption(String selector, String value) async {
    final selectElement = await findElement(selector);
    final option = await selectElement.findElement(
      By.cssSelector('option[value="$value"]'),
    );
    await option.click();
  }

  /// Checks a checkbox or radio button.
  @override
  Future<void> check(String selector) async {
    final element = await findElement(selector);
    final isSelected = await element.selected;
    if (isSelected == false) {
      await element.click();
    }
  }

  /// Unchecks a checkbox.
  @override
  Future<void> uncheck(String selector) async {
    final element = await findElement(selector);
    final isSelected = await element.selected;
    if (isSelected == true) {
      await element.click();
    }
  }

  /// Fills multiple form fields at once.
  @override
  Future<void> fillForm(Map<String, String> data) async {
    for (final entry in data.entries) {
      await type(entry.key, entry.value);
    }
  }

  /// Submits a form.
  @override
  Future<void> submitForm([String? selector]) async {
    if (selector != null) {
      final form = await findElement(selector);
      await driver.execute('arguments[0].submit();', [form]);
    } else {
      final form = await driver.findElement(const By.tagName('form'));
      await driver.execute('arguments[0].submit();', [form]);
    }
  }

  /// Uploads a file to a file input element.
  @override
  Future<void> uploadFile(String selector, String filePath) async {
    final element = await findElement(selector);
    await element.sendKeys(filePath);
  }

  /// Scrolls to a specific element on the page.
  @override
  Future<void> scrollTo(String selector) async {
    final element = await findElement(selector);
    await driver.execute('arguments[0].scrollIntoView();', [element]);
  }

  /// Scrolls to the top of the page.
  @override
  Future<void> scrollToTop() async {
    await driver.execute('window.scrollTo(0, 0);', []);
  }

  /// Scrolls to the bottom of the page.
  @override
  Future<void> scrollToBottom() async {
    await driver.execute('window.scrollTo(0, document.body.scrollHeight);', []);
  }

  // ========================================
  // Enhanced waiting methods
  // ========================================

  /// Waits for an element to appear in the DOM.
  @override
  Future<void> waitForElement(String selector, {Duration? timeout}) async {
    await waiter.waitFor(selector, timeout);
  }

  /// Waits for specific text to appear on the page.
  @override
  Future<void> waitForText(String text, {Duration? timeout}) async {
    await waiter.waitForText(text, timeout);
  }

  /// Waits for the browser to navigate to a specific URL.
  @override
  Future<void> waitForUrl(String url, {Duration? timeout}) async {
    await waiter.waitForLocation(url, timeout);
  }

  /// Pauses execution for the specified duration.
  @override
  Future<void> pause(Duration duration) async {
    await waiter.wait(duration);
  }

  // ========================================
  // Debugging helper methods
  // ========================================

  /// Takes a screenshot of the current page.
  @override
  Future<void> takeScreenshot([String? name]) async {
    _logger.logInfo(
      'Taking screenshot',
      details: name != null ? 'name: $name' : null,
    );

    try {
      final screenshotPath = await _screenshotManager.captureScreenshot(
        driver,
        name: name,
        context: 'manual',
      );

      if (screenshotPath != null) {
        _logger.logInfo('Screenshot saved', details: screenshotPath);
      } else {
        _logger.logWarning('Screenshot capture failed');
      }
    } catch (e) {
      _logger.logError('Failed to take screenshot', error: e);
      throw EnhancedBrowserException(
        'Failed to take screenshot',
        action: 'takeScreenshot',
        cause: e,
      );
    }
  }

  /// Dumps the current page source to the console or log.
  @override
  Future<void> dumpPageSource() async {
    _logger.logInfo('Dumping page source');

    try {
      final source = await getPageSource();
      print('=== PAGE SOURCE ===');
      print(source);
      print('=== END PAGE SOURCE ===');

      _logger.logInfo('Page source dumped successfully');
    } catch (e) {
      _logger.logError('Failed to dump page source', error: e);
      throw EnhancedBrowserException(
        'Failed to dump page source',
        action: 'dumpPageSource',
        cause: e,
      );
    }
  }

  /// Gets the text content of an element.
  @override
  Future<String> getElementText(String selector) async {
    _logger.logInfo('Getting element text', selector: selector);

    try {
      final element = await findElement(selector);
      final text = await element.text;

      _logger.logInfo(
        'Element text retrieved',
        selector: selector,
        details: 'text: "$text"',
      );
      return text as String;
    } catch (e) {
      final screenshotPath = await _screenshotManager.captureFailureScreenshot(
        driver,
        action: 'getElementText',
        selector: selector,
      );

      _logger.logError(
        'Failed to get element text',
        action: 'getElementText',
        selector: selector,
        error: e,
      );

      throw EnhancedBrowserException(
        'Failed to get text from element: $selector',
        selector: selector,
        action: 'getElementText',
        screenshotPath: screenshotPath,
        cause: e,
      );
    }
  }

  /// Gets the value of an attribute from an element.
  @override
  Future<String?> getElementAttribute(String selector, String attribute) async {
    _logger.logInfo(
      'Getting element attribute',
      selector: selector,
      details: 'attribute: $attribute',
    );

    try {
      final element = await findElement(selector);
      final attributes = await element.attributes;
      final attributeMap = attributes as Map<String, String>;
      final value = attributeMap[attribute];

      _logger.logInfo(
        'Element attribute retrieved',
        selector: selector,
        details: 'attribute: $attribute, value: "$value"',
      );
      return value;
    } catch (e) {
      final screenshotPath = await _screenshotManager.captureFailureScreenshot(
        driver,
        action: 'getElementAttribute',
        selector: selector,
      );

      _logger.logError(
        'Failed to get element attribute',
        action: 'getElementAttribute',
        selector: selector,
        details: 'attribute: $attribute',
        error: e,
      );

      throw EnhancedBrowserException(
        'Failed to get attribute "$attribute" from element: $selector',
        selector: selector,
        action: 'getElementAttribute',
        screenshotPath: screenshotPath,
        details: 'attribute: $attribute',
        cause: e,
      );
    }
  }

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
