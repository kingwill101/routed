// import 'package:test/test.dart';
// import 'package:webdriver/async_core.dart' show WebDriver, WebElement, By;

// import 'browser_assertions.dart';
// import 'browser_config.dart';
// import 'dialogs.dart';
// import 'frame.dart';
// import 'keyboard.dart';
// import 'mouse.dart';
// import 'waiter.dart';
// import 'window.dart';

// class Browser with BrowserAssertions {
//   final WebDriver driver;
//   final BrowserConfig config;

//   // Feature handlers
//   late final keyboard = Keyboard(this);
//   late final mouse = Mouse(this);
//   late final dialogs = DialogHandler(this);
//   late final frames = FrameHandler(this);
//   late final waiter = BrowserWaiter(this);
//   late final window = WindowManager(this);

//   Browser(this.driver, this.config);

//   // Navigation
//   Future<Browser> visit(String url) async {
//     String finalUrl = url;
//     if (config.baseUrl != null) {
//       if (!(url.startsWith('http://') || url.startsWith('https://')) &&
//           config.baseUrl!.isNotEmpty) {
//         final base = config.baseUrl!.endsWith('/')
//             ? config.baseUrl!.substring(0, config.baseUrl!.length - 1)
//             : config.baseUrl;
//         final path = url.startsWith('/') ? url : '/$url';
//         finalUrl = '$base$path';
//       }
//     }
//     await driver.get(finalUrl);
//     return this;
//   }

//   Future<Browser> back() async {
//     await driver.back();
//     return this;
//   }

//   Future<Browser> forward() async {
//     await driver.forward();
//     return this;
//   }

//   Future<Browser> refresh() async {
//     await driver.refresh();
//     return this;
//   }

//   // Core interactions
//   Future<Browser> click(String selector) async {
//     final element = await findElement(selector);
//     await element.click();
//     return this;
//   }

//   Future<Browser> type(String selector, String value) async {
//     final element = await findElement(selector);
//     await element.clear();
//     await element.sendKeys(value);
//     return this;
//   }

//   // Helper methods
//   Future<WebElement> findElement(String selector) async {
//     try {
//       if (selector.startsWith('@')) {
//         return await driver
//             .findElement(By.cssSelector('[dusk="${selector.substring(1)}"]'));
//       }
//       return await driver.findElement(By.cssSelector(selector));
//     } catch (e) {
//       throw Exception('Could not find element: $selector');
//     }
//   }

//   Future<bool> isPresent(String selector) async {
//     try {
//       await findElement(selector);
//       return true;
//     } catch (_) {
//       return false;
//     }
//   }

//   Future<void> waitUntil(Future<bool> Function() predicate,
//       {Duration? timeout,
//       Duration interval = const Duration(milliseconds: 100)}) async {
//     timeout ??= const Duration(seconds: 5);
//     final endTime = DateTime.now().add(timeout);

//     while (DateTime.now().isBefore(endTime)) {
//       if (await predicate()) return;
//       await Future.delayed(interval);
//     }

//     throw TimeoutError('Timed out waiting for condition');
//   }

//   Future<String> getPageSource() async => await driver.pageSource;

//   Future<String> getCurrentUrl() async => await driver.currentUrl;

//   Future<dynamic> executeScript(String script) async {
//     return await driver.execute(script, []);
//   }

//   @override
//   Future<Browser> assertTitle(String title) async {
//     expect(await driver.title, equals(title),
//         reason: 'Page title should be "$title"');
//     return this;
//   }

//   @override
//   Future<Browser> assertTitleContains(String text) async {
//     expect(await driver.title, contains(text),
//         reason: 'Page title should contain "$text"');
//     return this;
//   }

//   @override
//   Future<Browser> assertUrlIs(String url) async {
//     expect(await getCurrentUrl(), equals(url),
//         reason: 'Current URL should be "$url"');
//     return this;
//   }

//   @override
//   Future<Browser> assertSee(String text) async {
//     expect(await getPageSource(), contains(text),
//         reason: 'Page should contain text "$text"');
//     return this;
//   }

//   @override
//   Future<Browser> assertDontSee(String text) async {
//     expect(await getPageSource(), isNot(contains(text)),
//         reason: 'Page should not contain text "$text"');
//     return this;
//   }

//   @override
//   Future<Browser> assertAuthenticated([String? guard]) async {
//     // Implementation depends on your authentication setup
//     return this;
//   }

//   @override
//   Future<Browser> assertGuest([String? guard]) async {
//     // Implementation depends on your authentication setup
//     return this;
//   }

//   @override
//   Future<Browser> assertChecked(String field) async {
//     final element = await findElement(field);
//     expect(await element.selected, isTrue,
//         reason: 'Field "$field" should be checked');
//     return this;
//   }

//   @override
//   Future<Browser> assertNotChecked(String field) async {
//     final element = await findElement(field);
//     expect(await element.selected, isFalse,
//         reason: 'Field "$field" should not be checked');
//     return this;
//   }

//   @override
//   Future<Browser> assertDisabled(String field) async {
//     final element = await findElement(field);
//     expect(await element.enabled, isFalse,
//         reason: 'Field "$field" should be disabled');
//     return this;
//   }

//   @override
//   Future<Browser> assertEnabled(String field) async {
//     final element = await findElement(field);
//     expect(await element.enabled, isTrue,
//         reason: 'Field "$field" should be enabled');
//     return this;
//   }

//   @override
//   Future<Browser> assertDontSeeIn(String selector, String text) async {
//     final element = await findElement(selector);
//     final elementText = await element.text;
//     expect(elementText, isNot(contains(text)),
//         reason: 'Element "$selector" should not contain text "$text"');
//     return this;
//   }

//   @override
//   Future<Browser> assertSeeIn(String selector, String text) async {
//     final element = await findElement(selector);
//     final elementText = await element.text;
//     expect(elementText, contains(text),
//         reason: 'Element "$selector" should contain text "$text"');
//     return this;
//   }

//   @override
//   Future<Browser> assertPathIs(String path) async {
//     final url = await getCurrentUrl();
//     expect(Uri.parse(url).path, equals(path),
//         reason: 'URL path should be "$path"');
//     return this;
//   }

//   @override
//   Future<Browser> assertPathBeginsWith(String path) async {
//     final url = await getCurrentUrl();
//     expect(Uri.parse(url).path, startsWith(path),
//         reason: 'URL path should begin with "$path"');
//     return this;
//   }

//   @override
//   Future<Browser> assertPathEndsWith(String path) async {
//     final url = await getCurrentUrl();
//     expect(Uri.parse(url).path, endsWith(path),
//         reason: 'URL path should end with "$path"');
//     return this;
//   }

//   @override
//   Future<Browser> assertQueryStringHas(String name, [String? value]) async {
//     final url = await getCurrentUrl();
//     final params = Uri.parse(url).queryParameters;
//     expect(params, contains(name),
//         reason: 'URL should contain query parameter "$name"');
//     if (value != null) {
//       expect(params[name], equals(value),
//           reason: 'Query parameter "$name" should have value "$value"');
//     }
//     return this;
//   }

//   @override
//   Future<Browser> assertQueryStringMissing(String name) async {
//     final url = await getCurrentUrl();
//     final params = Uri.parse(url).queryParameters;
//     expect(params, (p) => !p.containsKey(name),
//         reason: 'URL should not contain query parameter "$name"');
//     return this;
//   }

//   @override
//   Future<Browser> assertSeeAnythingIn(String selector) async {
//     final element = await findElement(selector);
//     final text = await element.text;
//     expect(text.trim(), isNotEmpty,
//         reason: 'Element "$selector" should not be empty');
//     return this;
//   }

//   @override
//   Future<Browser> assertSeeNothingIn(String selector) async {
//     final element = await findElement(selector);
//     final text = await element.text;
//     expect(text.trim(), isEmpty, reason: 'Element "$selector" should be empty');
//     return this;
//   }

//   @override
//   Future<Browser> assertPresent(String selector) async {
//     expect(await isPresent(selector), isTrue,
//         reason: 'Element "$selector" should be present');
//     return this;
//   }

//   @override
//   Future<Browser> assertNotPresent(String selector) async {
//     expect(await isPresent(selector), isFalse,
//         reason: 'Element "$selector" should not be present');
//     return this;
//   }

//   @override
//   Future<Browser> assertVisible(String selector) async {
//     final element = await findElement(selector);
//     expect(await element.displayed, isTrue,
//         reason: 'Element "$selector" should be visible');
//     return this;
//   }

//   @override
//   Future<Browser> assertMissing(String selector) async {
//     expect(await isPresent(selector), isFalse,
//         reason: 'Element "$selector" should be missing');
//     return this;
//   }

//   @override
//   Future<Browser> assertInputPresent(String name) async {
//     expect(await isPresent('input[name="$name"]'), isTrue,
//         reason: 'Input field "$name" should be present');
//     return this;
//   }

//   @override
//   Future<Browser> assertInputMissing(String name) async {
//     expect(await isPresent('input[name="$name"]'), isFalse,
//         reason: 'Input field "$name" should be missing');
//     return this;
//   }

//   @override
//   Future<Browser> assertInputValue(String field, String value) async {
//     final element = await findElement(field);
//     expect(element.attributes['value'], equals(value),
//         reason: 'Input field "$field" should have value "$value"');
//     return this;
//   }

//   @override
//   Future<Browser> assertInputValueIsNot(String field, String value) async {
//     final element = await findElement(field);
//     expect(element.attributes['value'], isNot(equals(value)),
//         reason: 'Input field "$field" should not have value "$value"');
//     return this;
//   }

//   @override
//   Future<Browser> assertRadioSelected(String field, String value) async {
//     final element =
//         await findElement('input[type="radio"][name="$field"][value="$value"]');
//     expect(await element.selected, isTrue,
//         reason: 'Radio button "$field" with value "$value" should be selected');
//     return this;
//   }

//   @override
//   Future<Browser> assertRadioNotSelected(String field, String value) async {
//     final element =
//         await findElement('input[type="radio"][name="$field"][value="$value"]');
//     expect(await element.selected, isFalse,
//         reason:
//             'Radio button "$field" with value "$value" should not be selected');
//     return this;
//   }

//   @override
//   Future<Browser> assertSelected(String field, String value) async {
//     final element = await findElement('$field option[value="$value"]');
//     expect(await element.selected, isTrue,
//         reason:
//             'Option with value "$value" in field "$field" should be selected');
//     return this;
//   }

//   @override
//   Future<Browser> assertNotSelected(String field, String value) async {
//     final element = await findElement('$field option[value="$value"]');
//     expect(await element.selected, isFalse,
//         reason:
//             'Option with value "$value" in field "$field" should not be selected');
//     return this;
//   }

//   @override
//   Future<Browser> assertFocused(String field) async {
//     final element = await findElement(field);
//     final activeElement = await driver.activeElement;
//     if (activeElement == null) fail("$field is not the active element");
//     expect(await element.equals(activeElement), isTrue,
//         reason: 'Field "$field" should be focused');
//     return this;
//   }

//   @override
//   Future<Browser> assertNotFocused(String field) async {
//     final element = await findElement(field);
//     final activeElement = await driver.activeElement;
//     if (activeElement == null) return this;
//     expect(await element.equals(activeElement), isFalse,
//         reason: 'Field "$field" should not be focused');
//     return this;
//   }

//   @override
//   Future<Browser> screenshot(String name) async {
//     final bytes = await driver.captureScreenshotAsList();
//     // TODO: Save screenshot bytes to file with name
//     return this;
//   }

//   @override
//   Future<Browser> source(String name) async {
//     final source = await getPageSource();
//     // TODO: Save source to file with name
//     return this;
//   }
// }

// class TimeoutError extends Error {
//   final String message;

//   TimeoutError(this.message);

//   @override
//   String toString() => message;
// }
