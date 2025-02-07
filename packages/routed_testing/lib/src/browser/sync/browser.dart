import 'dart:async' show FutureOr, TimeoutException;
import 'dart:io' show sleep;

import 'package:routed_testing/src/browser/browser_config.dart';
import 'package:routed_testing/src/browser/interfaces/download.dart';
import 'package:routed_testing/src/browser/interfaces/emulation.dart';
import 'package:routed_testing/src/browser/interfaces/network.dart';
import 'package:routed_testing/src/browser/sync/assertions.dart';
import 'package:routed_testing/src/browser/sync/cookie.dart';
import 'package:routed_testing/src/browser/sync/local_storage.dart';
import 'package:routed_testing/src/browser/sync/session_storage.dart';
import 'package:routed_testing/src/browser/utils.dart';
import 'package:webdriver/sync_core.dart' show WebDriver, WebElement, By;

import '../interfaces/browser.dart';
import 'dialog.dart';
import 'frame.dart';
import 'keyboard.dart';
import 'mouse.dart';
import 'waiter.dart';
import 'window.dart';

class SyncBrowser with SyncBrowserAssertions implements Browser {
  final WebDriver driver;
  final BrowserConfig config;

  @override
  late final keyboard = SyncKeyboard(this);
  @override
  late final mouse = SyncMouse(this);
  @override
  late final dialogs = SyncDialogHandler(this);
  @override
  late final frames = SyncFrameHandler(this);
  @override
  late final waiter = SyncBrowserWaiter(this);
  @override
  late final window = SyncWindowManager(this);
  @override
  late final cookies = SyncCookieHandler(this);
  @override
  late final localStorage = SyncLocalStorageHandler(this);
  @override
  late final sessionStorage = SyncSessionStorageHandler(this);

  SyncBrowser(this.driver, this.config);

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

  @override
  void visit(String url) => driver.get(resolveUrl(url, config: config));

  @override
  void back() => driver.back();

  @override
  void forward() => driver.forward();

  @override
  void refresh() => driver.refresh();

  @override
  void click(String selector) {
    final element = findElement(selector);
    element.click();
  }

  @override
  void type(String selector, String value) {
    final element = findElement(selector);
    element.clear();
    element.sendKeys(value);
  }

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

  @override
  bool isPresent(String selector) {
    try {
      findElement(selector);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  String getPageSource() => driver.pageSource;

  @override
  String getCurrentUrl() => driver.currentUrl;

  @override
  String getTitle() => driver.title;

  @override
  dynamic executeScript(String script) => driver.execute(script, []);

  @override
  void quit() => driver.quit();

  @override
  // TODO: implement download
  Download get download => throw UnimplementedError();

  @override
  // TODO: implement emulation
  Emulation get emulation => throw UnimplementedError();

  @override
  // TODO: implement network
  Network get network => throw UnimplementedError();
}
