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

class AsyncBrowser with AsyncBrowserAssertions implements Browser {
  final WebDriver driver;
  final BrowserConfig config;

  @override
  late final keyboard = AsyncKeyboard(this);

  @override
  late final mouse = AsyncMouse(this);

  @override
  late final dialogs = AsyncDialogHandler(this);

  @override
  late final frames = AsyncFrameHandler(this);

  @override
  late final waiter = AsyncBrowserWaiter(this);

  @override
  late final window = AsyncWindowManager(this);

  @override
  late final cookies = AsyncCookieHandler(this);

  @override
  late final localStorage = AsyncLocalStorageHandler(this);

  @override
  late final sessionStorage = AsyncSessionStorageHandler(this);

  AsyncBrowser(this.driver, this.config);

  @override
  Future<void> visit(String url) => driver.get(resolveUrl(url, config: config));

  @override
  Future<void> back() => driver.back();

  @override
  Future<void> forward() => driver.forward();

  @override
  Future<void> refresh() => driver.refresh();

  @override
  Future<void> click(String selector) async {
    final element = await findElement(selector);
    await element.click();
  }

  @override
  Future<void> type(String selector, String value) async {
    final element = await findElement(selector);
    await element.clear();
    await element.sendKeys(value);
  }

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

  @override
  Future<bool> isPresent(String selector) async {
    try {
      await findElement(selector);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> getPageSource() => driver.pageSource;

  @override
  Future<String> getCurrentUrl() => driver.currentUrl;

  @override
  Future<String> getTitle() => driver.title;

  @override
  Future<dynamic> executeScript(String script) => driver.execute(script, []);

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

  @override
  Future<void> quit() => driver.quit();

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
