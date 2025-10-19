import 'dart:async';

import 'package:server_testing/src/browser/interfaces/assertions.dart';
import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:server_testing/src/browser/interfaces/cookie.dart';
import 'package:server_testing/src/browser/interfaces/dialog.dart';
import 'package:server_testing/src/browser/interfaces/download.dart';
import 'package:server_testing/src/browser/interfaces/emulation.dart';
import 'package:server_testing/src/browser/interfaces/frame.dart';
import 'package:server_testing/src/browser/interfaces/keyboard.dart';
import 'package:server_testing/src/browser/interfaces/local_storage.dart';
import 'package:server_testing/src/browser/interfaces/mouse.dart';
import 'package:server_testing/src/browser/interfaces/network.dart';
import 'package:server_testing/src/browser/interfaces/session_storage.dart';
import 'package:server_testing/src/browser/interfaces/waiter.dart';
import 'package:server_testing/src/browser/interfaces/window.dart';
import 'package:test/test.dart';

/// Mock implementation of Browser for testing the interface methods
class MockBrowser extends BrowserAssertions with Browser {
  final List<String> _actions = [];
  final Map<String, String> _elementTexts = {};
  final Map<String, Map<String, String>> _elementAttributes = {};
  final Set<String> _presentElements = {};
  final Set<String> _checkedElements = {};
  final Set<String> _enabledElements = {};
  String _currentUrl = '';
  String _pageTitle = '';
  String _pageSource = '';
  late final MockBrowserWaiter _waiter;

  MockBrowser() {
    _waiter = MockBrowserWaiter();
  }

  List<String> get actions => List.unmodifiable(_actions);

  void setElementText(String selector, String text) {
    _elementTexts[selector] = text;
  }

  void setElementAttribute(String selector, String attribute, String value) {
    _elementAttributes.putIfAbsent(selector, () => {})[attribute] = value;
  }

  void setElementPresent(String selector, bool present) {
    if (present) {
      _presentElements.add(selector);
    } else {
      _presentElements.remove(selector);
    }
  }

  void setElementChecked(String selector, bool checked) {
    if (checked) {
      _checkedElements.add(selector);
    } else {
      _checkedElements.remove(selector);
    }
  }

  void setElementEnabled(String selector, bool enabled) {
    if (enabled) {
      _enabledElements.add(selector);
    } else {
      _enabledElements.remove(selector);
    }
  }

  void setCurrentUrl(String url) => _currentUrl = url;

  void setPageTitle(String title) => _pageTitle = title;

  void setPageSource(String source) => _pageSource = source;

  // Browser interface implementation
  @override
  FutureOr<void> visit(String url) {
    _actions.add('visit:$url');
    _currentUrl = url;
  }

  @override
  FutureOr<void> back() {
    _actions.add('back');
  }

  @override
  FutureOr<void> forward() {
    _actions.add('forward');
  }

  @override
  FutureOr<void> refresh() {
    _actions.add('refresh');
  }

  @override
  FutureOr<void> click(String selector) {
    _actions.add('click:$selector');
  }

  @override
  FutureOr<void> type(String selector, String value) {
    _actions.add('type:$selector:$value');
  }

  @override
  FutureOr<dynamic> findElement(String selector) =>
      MockWebElement(selector, this);

  @override
  FutureOr<bool> isPresent(String selector) =>
      _presentElements.contains(selector);

  @override
  FutureOr<String> getPageSource() => _pageSource;

  @override
  FutureOr<String> getCurrentUrl() => _currentUrl;

  @override
  FutureOr<String> getTitle() => _pageTitle;

  @override
  FutureOr<dynamic> executeScript(String script) {
    _actions.add('executeScript:$script');
    return 'script_result';
  }

  @override
  FutureOr<void> waitUntil(
    FutureOr<bool> Function() predicate, {
    Duration? timeout,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    _actions.add('waitUntil:${timeout?.inMilliseconds}ms');
  }

  @override
  FutureOr<void> quit() {
    _actions.add('quit');
  }

  // New convenience methods implementation
  @override
  FutureOr<void> clickLink(String linkText) {
    _actions.add('clickLink:$linkText');
  }

  @override
  FutureOr<void> selectOption(String selector, String value) {
    _actions.add('selectOption:$selector:$value');
  }

  @override
  FutureOr<void> check(String selector) {
    _actions.add('check:$selector');
  }

  @override
  FutureOr<void> uncheck(String selector) {
    _actions.add('uncheck:$selector');
  }

  @override
  FutureOr<void> fillForm(Map<String, String> data) {
    final entries = data.entries.map((e) => '${e.key}=${e.value}').join(',');
    _actions.add('fillForm:$entries');
  }

  @override
  FutureOr<void> submitForm([String? selector]) {
    _actions.add('submitForm:${selector ?? 'default'}');
  }

  @override
  FutureOr<void> uploadFile(String selector, String filePath) {
    _actions.add('uploadFile:$selector:$filePath');
  }

  @override
  FutureOr<void> scrollTo(String selector) {
    _actions.add('scrollTo:$selector');
  }

  @override
  FutureOr<void> scrollToTop() {
    _actions.add('scrollToTop');
  }

  @override
  FutureOr<void> scrollToBottom() {
    _actions.add('scrollToBottom');
  }

  @override
  FutureOr<void> waitForElement(String selector, {Duration? timeout}) {
    _actions.add(
      'waitForElement:$selector:${timeout?.inMilliseconds ?? 'null'}ms',
    );
  }

  @override
  FutureOr<void> waitForText(String text, {Duration? timeout}) {
    _actions.add('waitForText:$text:${timeout?.inMilliseconds ?? 'null'}ms');
  }

  @override
  FutureOr<void> waitForUrl(String url, {Duration? timeout}) {
    _actions.add('waitForUrl:$url:${timeout?.inMilliseconds ?? 'null'}ms');
  }

  @override
  FutureOr<void> pause(Duration duration) {
    _actions.add('pause:${duration.inMilliseconds}ms');
  }

  @override
  FutureOr<void> takeScreenshot([String? name]) {
    _actions.add('takeScreenshot:${name ?? 'auto'}');
  }

  @override
  FutureOr<void> dumpPageSource() {
    _actions.add('dumpPageSource');
  }

  @override
  FutureOr<String> getElementText(String selector) {
    _actions.add('getElementText:$selector');
    return _elementTexts[selector] ?? '';
  }

  @override
  FutureOr<String?> getElementAttribute(String selector, String attribute) {
    _actions.add('getElementAttribute:$selector:$attribute');
    return _elementAttributes[selector]?[attribute];
  }

  // Handler getters (simplified for testing)
  @override
  Cookie get cookies => MockCookie();

  @override
  LocalStorage get localStorage => MockLocalStorage();

  @override
  SessionStorage get sessionStorage => MockSessionStorage();

  @override
  Keyboard get keyboard => MockKeyboard();

  @override
  Mouse get mouse => MockMouse();

  @override
  DialogHandler get dialogs => MockDialogHandler();

  @override
  FrameHandler get frames => MockFrameHandler();

  @override
  WindowManager get window => MockWindowManager();

  @override
  BrowserWaiter get waiter => _waiter;

  @override
  Network get network => MockNetwork();

  @override
  Emulation get emulation => MockEmulation();

  @override
  Download get download => MockDownload();

  // BrowserAssertions implementation (simplified for testing)
  @override
  FutureOr<Browser> assertTitle(String title) {
    _actions.add('assertTitle:$title');
    return this;
  }

  @override
  FutureOr<Browser> assertTitleContains(String text) {
    _actions.add('assertTitleContains:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertUrlIs(String url) {
    _actions.add('assertUrlIs:$url');
    return this;
  }

  @override
  FutureOr<Browser> assertPathIs(String path) {
    _actions.add('assertPathIs:$path');
    return this;
  }

  @override
  FutureOr<Browser> assertPathBeginsWith(String path) {
    _actions.add('assertPathBeginsWith:$path');
    return this;
  }

  @override
  FutureOr<Browser> assertPathEndsWith(String path) {
    _actions.add('assertPathEndsWith:$path');
    return this;
  }

  @override
  FutureOr<Browser> assertQueryStringHas(String name, [String? value]) {
    _actions.add('assertQueryStringHas:$name:${value ?? 'any'}');
    return this;
  }

  @override
  FutureOr<Browser> assertQueryStringMissing(String name) {
    _actions.add('assertQueryStringMissing:$name');
    return this;
  }

  @override
  FutureOr<Browser> assertSee(String text) {
    _actions.add('assertSee:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertDontSee(String text) {
    _actions.add('assertDontSee:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertSeeIn(String selector, String text) {
    _actions.add('assertSeeIn:$selector:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertDontSeeIn(String selector, String text) {
    _actions.add('assertDontSeeIn:$selector:$text');
    return this;
  }

  @override
  FutureOr<Browser> assertSeeAnythingIn(String selector) {
    _actions.add('assertSeeAnythingIn:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertSeeNothingIn(String selector) {
    _actions.add('assertSeeNothingIn:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertPresent(String selector) {
    _actions.add('assertPresent:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertNotPresent(String selector) {
    _actions.add('assertNotPresent:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertVisible(String selector) {
    _actions.add('assertVisible:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertMissing(String selector) {
    _actions.add('assertMissing:$selector');
    return this;
  }

  @override
  FutureOr<Browser> assertInputPresent(String name) {
    _actions.add('assertInputPresent:$name');
    return this;
  }

  @override
  FutureOr<Browser> assertInputMissing(String name) {
    _actions.add('assertInputMissing:$name');
    return this;
  }

  @override
  FutureOr<Browser> assertInputValue(String field, String value) {
    _actions.add('assertInputValue:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertInputValueIsNot(String field, String value) {
    _actions.add('assertInputValueIsNot:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertChecked(String field) {
    _actions.add('assertChecked:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertNotChecked(String field) {
    _actions.add('assertNotChecked:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertRadioSelected(String field, String value) {
    _actions.add('assertRadioSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertRadioNotSelected(String field, String value) {
    _actions.add('assertRadioNotSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertSelected(String field, String value) {
    _actions.add('assertSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertNotSelected(String field, String value) {
    _actions.add('assertNotSelected:$field:$value');
    return this;
  }

  @override
  FutureOr<Browser> assertEnabled(String field) {
    _actions.add('assertEnabled:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertDisabled(String field) {
    _actions.add('assertDisabled:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertFocused(String field) {
    _actions.add('assertFocused:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertNotFocused(String field) {
    _actions.add('assertNotFocused:$field');
    return this;
  }

  @override
  FutureOr<Browser> assertAuthenticated([String? guard]) {
    _actions.add('assertAuthenticated:${guard ?? 'default'}');
    return this;
  }

  @override
  FutureOr<Browser> assertGuest([String? guard]) {
    _actions.add('assertGuest:${guard ?? 'default'}');
    return this;
  }
}

class MockWebElement {
  final String selector;
  final MockBrowser browser;

  MockWebElement(this.selector, this.browser);

  String get text => browser._elementTexts[selector] ?? '';
}

// Mock implementations for all handler interfaces
class MockCookie implements Cookie {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockLocalStorage implements LocalStorage {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockSessionStorage implements SessionStorage {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockKeyboard implements Keyboard {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockMouse implements Mouse {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockDialogHandler implements DialogHandler {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockFrameHandler implements FrameHandler {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockWindowManager implements WindowManager {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockNetwork implements Network {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockEmulation implements Emulation {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockDownload implements Download {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class MockBrowserWaiter implements BrowserWaiter {
  final List<String> _actions = [];

  List<String> get actions => List.unmodifiable(_actions);

  @override
  FutureOr<void> wait(Duration timeout) {
    _actions.add('wait:${timeout.inMilliseconds}ms');
  }

  @override
  FutureOr<void> waitFor(String selector, [Duration? timeout]) {
    _actions.add('waitFor:$selector:${timeout?.inMilliseconds ?? 'null'}ms');
  }

  @override
  FutureOr<void> waitUntilMissing(String selector, [Duration? timeout]) {
    _actions.add(
      'waitUntilMissing:$selector:${timeout?.inMilliseconds ?? 'null'}ms',
    );
  }

  @override
  FutureOr<void> waitForText(String text, [Duration? timeout]) {
    _actions.add('waitForText:$text:${timeout?.inMilliseconds ?? 'null'}ms');
  }

  @override
  FutureOr<void> waitForLocation(String path, [Duration? timeout]) {
    _actions.add(
      'waitForLocation:$path:${timeout?.inMilliseconds ?? 'null'}ms',
    );
  }

  @override
  FutureOr<void> waitForReload(WaiterCallback callback) {
    _actions.add('waitForReload');
  }

  @override
  FutureOr<void> waitForElement(String selector, {Duration? timeout}) {
    return waitFor(selector, timeout);
  }

  @override
  FutureOr<void> waitForUrl(String url, {Duration? timeout}) {
    return waitForLocation(url, timeout);
  }

  @override
  FutureOr<void> pause(Duration duration) {
    return wait(duration);
  }
}

void main() {
  group('Enhanced Browser Interface', () {
    late MockBrowser browser;

    setUp(() {
      browser = MockBrowser();
    });

    group('Convenience Methods', () {
      test('clickLink should record the action', () async {
        await browser.clickLink('Sign Out');
        expect(browser.actions, contains('clickLink:Sign Out'));
      });

      test('selectOption should record selector and value', () async {
        await browser.selectOption('select[name="country"]', 'US');
        expect(
          browser.actions,
          contains('selectOption:select[name="country"]:US'),
        );
      });

      test('check should record the selector', () async {
        await browser.check('input[name="terms"]');
        expect(browser.actions, contains('check:input[name="terms"]'));
      });

      test('uncheck should record the selector', () async {
        await browser.uncheck('input[name="notifications"]');
        expect(
          browser.actions,
          contains('uncheck:input[name="notifications"]'),
        );
      });

      test('fillForm should record all field data', () async {
        await browser.fillForm({
          'input[name="email"]': 'user@example.com',
          'input[name="password"]': 'secret123',
        });
        expect(
          browser.actions,
          contains(
            'fillForm:input[name="email"]=user@example.com,input[name="password"]=secret123',
          ),
        );
      });

      test(
        'submitForm should record default when no selector provided',
        () async {
          await browser.submitForm();
          expect(browser.actions, contains('submitForm:default'));
        },
      );

      test(
        'submitForm should record specific selector when provided',
        () async {
          await browser.submitForm('#login-form');
          expect(browser.actions, contains('submitForm:#login-form'));
        },
      );

      test('uploadFile should record selector and file path', () async {
        await browser.uploadFile('input[type="file"]', '/path/to/file.pdf');
        expect(
          browser.actions,
          contains('uploadFile:input[type="file"]:/path/to/file.pdf'),
        );
      });

      test('scrollTo should record the selector', () async {
        await browser.scrollTo('#footer');
        expect(browser.actions, contains('scrollTo:#footer'));
      });

      test('scrollToTop should record the action', () async {
        await browser.scrollToTop();
        expect(browser.actions, contains('scrollToTop'));
      });

      test('scrollToBottom should record the action', () async {
        await browser.scrollToBottom();
        expect(browser.actions, contains('scrollToBottom'));
      });
    });

    group('Enhanced Waiting Methods', () {
      test('waitForElement should record selector and timeout', () async {
        await browser.waitForElement('.loading-spinner');
        expect(
          browser.actions,
          contains('waitForElement:.loading-spinner:nullms'),
        );
      });

      test('waitForElement should record custom timeout', () async {
        await browser.waitForElement(
          '#success-message',
          timeout: const Duration(seconds: 5),
        );
        expect(
          browser.actions,
          contains('waitForElement:#success-message:5000ms'),
        );
      });

      test('waitForText should record text and timeout', () async {
        await browser.waitForText('Welcome back!');
        expect(browser.actions, contains('waitForText:Welcome back!:nullms'));
      });

      test('waitForText should record custom timeout', () async {
        await browser.waitForText(
          'Order confirmed',
          timeout: const Duration(seconds: 10),
        );
        expect(
          browser.actions,
          contains('waitForText:Order confirmed:10000ms'),
        );
      });

      test('waitForUrl should record url and timeout', () async {
        await browser.waitForUrl('/dashboard');
        expect(browser.actions, contains('waitForUrl:/dashboard:nullms'));
      });

      test('waitForUrl should record custom timeout', () async {
        await browser.waitForUrl(
          'https://example.com/success',
          timeout: const Duration(seconds: 15),
        );
        expect(
          browser.actions,
          contains('waitForUrl:https://example.com/success:15000ms'),
        );
      });

      test('pause should record the duration', () async {
        await browser.pause(const Duration(seconds: 2));
        expect(browser.actions, contains('pause:2000ms'));
      });

      test('pause should record milliseconds correctly', () async {
        await browser.pause(const Duration(milliseconds: 500));
        expect(browser.actions, contains('pause:500ms'));
      });
    });

    group('Debugging Helper Methods', () {
      test(
        'takeScreenshot should record auto name when none provided',
        () async {
          await browser.takeScreenshot();
          expect(browser.actions, contains('takeScreenshot:auto'));
        },
      );

      test('takeScreenshot should record custom name when provided', () async {
        await browser.takeScreenshot('login-page');
        expect(browser.actions, contains('takeScreenshot:login-page'));
      });

      test('dumpPageSource should record the action', () async {
        await browser.dumpPageSource();
        expect(browser.actions, contains('dumpPageSource'));
      });

      test('getElementText should return configured text', () async {
        browser.setElementText('.alert-message', 'Success!');
        final text = await browser.getElementText('.alert-message');
        expect(text, equals('Success!'));
        expect(browser.actions, contains('getElementText:.alert-message'));
      });

      test(
        'getElementText should return empty string for unknown elements',
        () async {
          final text = await browser.getElementText('.unknown');
          expect(text, equals(''));
        },
      );

      test('getElementAttribute should return configured attribute', () async {
        browser.setElementAttribute(
          'a.download',
          'href',
          'https://example.com/file.pdf',
        );
        final href = await browser.getElementAttribute('a.download', 'href');
        expect(href, equals('https://example.com/file.pdf'));
        expect(
          browser.actions,
          contains('getElementAttribute:a.download:href'),
        );
      });

      test(
        'getElementAttribute should return null for unknown attributes',
        () async {
          final attr = await browser.getElementAttribute(
            '.unknown',
            'nonexistent',
          );
          expect(attr, isNull);
        },
      );
    });

    group('Laravel Dusk-inspired Assertion Aliases', () {
      test('shouldSee should call assertSee', () async {
        final result = await browser.shouldSee('Welcome back!');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertSee:Welcome back!'));
      });

      test('shouldNotSee should call assertDontSee', () async {
        final result = await browser.shouldNotSee('Error occurred');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertDontSee:Error occurred'));
      });

      test('shouldHaveTitle should call assertTitle', () async {
        final result = await browser.shouldHaveTitle('Dashboard - MyApp');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertTitle:Dashboard - MyApp'));
      });

      test('shouldBeOn should call assertUrlIs', () async {
        final result = await browser.shouldBeOn('/dashboard');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertUrlIs:/dashboard'));
      });

      test('shouldHaveElement should call assertPresent', () async {
        final result = await browser.shouldHaveElement('.success-message');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertPresent:.success-message'));
      });

      test('shouldNotHaveElement should call assertNotPresent', () async {
        final result = await browser.shouldNotHaveElement('.error-message');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertNotPresent:.error-message'));
      });

      test('shouldHaveValue should call assertInputValue', () async {
        final result = await browser.shouldHaveValue(
          'input[name="email"]',
          'user@example.com',
        );
        expect(result, equals(browser));
        expect(
          browser.actions,
          contains('assertInputValue:input[name="email"]:user@example.com'),
        );
      });

      test('shouldBeChecked should call assertChecked', () async {
        final result = await browser.shouldBeChecked('input[name="terms"]');
        expect(result, equals(browser));
        expect(browser.actions, contains('assertChecked:input[name="terms"]'));
      });

      test('shouldBeEnabled should call assertEnabled', () async {
        final result = await browser.shouldBeEnabled('button[type="submit"]');
        expect(result, equals(browser));
        expect(
          browser.actions,
          contains('assertEnabled:button[type="submit"]'),
        );
      });

      test('shouldBeDisabled should call assertDisabled', () async {
        final result = await browser.shouldBeDisabled('input[name="readonly"]');
        expect(result, equals(browser));
        expect(
          browser.actions,
          contains('assertDisabled:input[name="readonly"]'),
        );
      });
    });

    group('Enhanced BrowserWaiter Methods', () {
      test('waitForElement should delegate to waitFor', () async {
        await browser.waiter.waitForElement('.loading-spinner');
        final waiter = browser.waiter as MockBrowserWaiter;
        expect(waiter.actions, contains('waitFor:.loading-spinner:nullms'));
      });

      test('waitForElement should pass timeout to waitFor', () async {
        await browser.waiter.waitForElement(
          '#success-message',
          timeout: const Duration(seconds: 5),
        );
        final waiter = browser.waiter as MockBrowserWaiter;
        expect(waiter.actions, contains('waitFor:#success-message:5000ms'));
      });

      test('waitForUrl should delegate to waitForLocation', () async {
        await browser.waiter.waitForUrl('/dashboard');
        final waiter = browser.waiter as MockBrowserWaiter;
        expect(waiter.actions, contains('waitForLocation:/dashboard:nullms'));
      });

      test('waitForUrl should pass timeout to waitForLocation', () async {
        await browser.waiter.waitForUrl(
          'https://example.com/success',
          timeout: const Duration(seconds: 15),
        );
        final waiter = browser.waiter as MockBrowserWaiter;
        expect(
          waiter.actions,
          contains('waitForLocation:https://example.com/success:15000ms'),
        );
      });

      test('pause should delegate to wait', () async {
        await browser.waiter.pause(const Duration(seconds: 2));
        final waiter = browser.waiter as MockBrowserWaiter;
        expect(waiter.actions, contains('wait:2000ms'));
      });
    });

    group('Method Chaining', () {
      test(
        'assertion methods should return browser instance for chaining',
        () async {
          // Test individual method returns
          var result = await browser.shouldSee('Welcome');
          expect(result, equals(browser));

          result = await browser.shouldHaveTitle('Dashboard');
          expect(result, equals(browser));

          result = await browser.shouldBeOn('/dashboard');
          expect(result, equals(browser));

          // Verify all actions were recorded
          expect(browser.actions, contains('assertSee:Welcome'));
          expect(browser.actions, contains('assertTitle:Dashboard'));
          expect(browser.actions, contains('assertUrlIs:/dashboard'));
        },
      );
    });
  });
}
