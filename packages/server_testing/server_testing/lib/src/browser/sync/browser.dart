import 'dart:async' show FutureOr, TimeoutException;
import 'dart:io' show sleep;

import 'package:server_testing/src/browser/browser_config.dart';
import 'package:server_testing/src/browser/browser_logger.dart'
    show EnhancedBrowserLogger;
import 'package:server_testing/src/browser/enhanced_exceptions.dart';
import 'package:server_testing/src/browser/interfaces/download.dart';
import 'package:server_testing/src/browser/interfaces/emulation.dart';
import 'package:server_testing/src/browser/interfaces/network.dart';
import 'package:server_testing/src/browser/screenshot_manager.dart';
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

  /// Logger for browser operations and debugging.
  late final EnhancedBrowserLogger _logger = EnhancedBrowserLogger(
    verboseLogging: config.verboseLogging,
    logDirectory: config.loggingEnabled ? config.logDir : null,
    enabled: config.loggingEnabled,
  );

  /// Manager for screenshot capture and automatic failure screenshots.
  late final ScreenshotManager _screenshotManager = ScreenshotManager(
    screenshotDirectory: config.screenshotDirectory,
    autoScreenshots: config.autoScreenshots,
  );

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
    _logger.logOperationStart('click', selector: selector);
    final startTime = DateTime.now();

    try {
      final element = findElement(selector);
      element.click();

      final duration = DateTime.now().difference(startTime);
      _logger.logOperationComplete(
        'click',
        selector: selector,
        duration: duration,
      );
    } catch (e) {
      final screenshotPath = _screenshotManager.captureFailureScreenshotSync(
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
  /// This is a blocking operation.
  @override
  void type(String selector, String value) {
    _logger.logOperationStart(
      'type',
      selector: selector,
      parameters: {'value': value},
    );
    final startTime = DateTime.now();

    try {
      final element = findElement(selector);
      element.clear();
      element.sendKeys(value);

      final duration = DateTime.now().difference(startTime);
      _logger.logOperationComplete(
        'type',
        selector: selector,
        duration: duration,
      );
    } catch (e) {
      final screenshotPath = _screenshotManager.captureFailureScreenshotSync(
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
  /// Throws an exception if no element is found. This is a blocking operation.
  @override
  WebElement findElement(String selector) {
    _logger.logInfo('Finding element', selector: selector);

    try {
      if (selector.startsWith('@')) {
        final duskSelector = '[dusk="${selector.substring(1)}"]';
        _logger.logInfo('Using dusk selector', selector: duskSelector);
        return driver.findElement(By.cssSelector(duskSelector));
      }
      return driver.findElement(By.cssSelector(selector));
    } catch (e) {
      final screenshotPath = _screenshotManager.captureFailureScreenshotSync(
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

  // ========================================
  // Laravel Dusk-inspired convenience methods
  // ========================================

  /// Clicks on a link containing the specified text.
  @override
  void clickLink(String linkText) {
    final element = driver.findElement(By.partialLinkText(linkText));
    element.click();
  }

  /// Selects an option from a dropdown/select element.
  @override
  void selectOption(String selector, String value) {
    final selectElement = findElement(selector);
    final option = selectElement.findElement(
      By.cssSelector('option[value="$value"]'),
    );
    option.click();
  }

  /// Checks a checkbox or radio button.
  @override
  void check(String selector) {
    final element = findElement(selector);
    if (!element.selected) {
      element.click();
    }
  }

  /// Unchecks a checkbox.
  @override
  void uncheck(String selector) {
    final element = findElement(selector);
    if (element.selected) {
      element.click();
    }
  }

  /// Fills multiple form fields at once.
  @override
  void fillForm(Map<String, String> data) {
    for (final entry in data.entries) {
      type(entry.key, entry.value);
    }
  }

  /// Submits a form.
  @override
  void submitForm([String? selector]) {
    if (selector != null) {
      final form = findElement(selector);
      driver.execute('arguments[0].submit();', [form]);
    } else {
      final form = driver.findElement(const By.tagName('form'));
      driver.execute('arguments[0].submit();', [form]);
    }
  }

  /// Uploads a file to a file input element.
  @override
  void uploadFile(String selector, String filePath) {
    final element = findElement(selector);
    element.sendKeys(filePath);
  }

  /// Scrolls to a specific element on the page.
  @override
  void scrollTo(String selector) {
    final element = findElement(selector);
    driver.execute('arguments[0].scrollIntoView();', [element]);
  }

  /// Scrolls to the top of the page.
  @override
  void scrollToTop() {
    driver.execute('window.scrollTo(0, 0);', []);
  }

  /// Scrolls to the bottom of the page.
  @override
  void scrollToBottom() {
    driver.execute('window.scrollTo(0, document.body.scrollHeight);', []);
  }

  // ========================================
  // Enhanced waiting methods
  // ========================================

  /// Waits for an element to appear in the DOM.
  @override
  void waitForElement(String selector, {Duration? timeout}) {
    waiter.waitFor(selector, timeout);
  }

  /// Waits for specific text to appear on the page.
  @override
  void waitForText(String text, {Duration? timeout}) {
    waiter.waitForText(text, timeout);
  }

  /// Waits for the browser to navigate to a specific URL.
  @override
  void waitForUrl(String url, {Duration? timeout}) {
    waiter.waitForLocation(url, timeout);
  }

  /// Pauses execution for the specified duration.
  @override
  void pause(Duration duration) {
    waiter.wait(duration);
  }

  // ========================================
  // Debugging helper methods
  // ========================================

  /// Takes a screenshot of the current page.
  @override
  void takeScreenshot([String? name]) {
    _logger.logInfo(
      'Taking screenshot',
      details: name != null ? 'name: $name' : null,
    );

    try {
      final screenshotPath = _screenshotManager.captureScreenshotSync(
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
  void dumpPageSource() {
    _logger.logInfo('Dumping page source');

    try {
      final source = getPageSource();
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
  String getElementText(String selector) {
    _logger.logInfo('Getting element text', selector: selector);

    try {
      final element = findElement(selector);
      final text = element.text;

      _logger.logInfo(
        'Element text retrieved',
        selector: selector,
        details: 'text: "$text"',
      );
      return text;
    } catch (e) {
      final screenshotPath = _screenshotManager.captureFailureScreenshotSync(
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
  String? getElementAttribute(String selector, String attribute) {
    _logger.logInfo(
      'Getting element attribute',
      selector: selector,
      details: 'attribute: $attribute',
    );

    try {
      final element = findElement(selector);
      final value = element.attributes[attribute];

      _logger.logInfo(
        'Element attribute retrieved',
        selector: selector,
        details: 'attribute: $attribute, value: "$value"',
      );
      return value;
    } catch (e) {
      final screenshotPath = _screenshotManager.captureFailureScreenshotSync(
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
