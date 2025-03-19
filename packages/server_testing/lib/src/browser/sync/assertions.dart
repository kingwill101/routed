import 'package:test/test.dart';

import '../interfaces/assertions.dart';
import '../interfaces/browser.dart';
import 'browser.dart' show SyncBrowser;

mixin SyncBrowserAssertions implements BrowserAssertions {
  SyncBrowser get browser => this as SyncBrowser;

  @override
  Browser assertTitle(String title) {
    expect(browser.getTitle(), equals(title));
    return browser;
  }

  @override
  Browser assertTitleContains(String text) {
    expect(browser.getTitle(), contains(text));
    return browser;
  }

  @override
  Browser assertUrlIs(String url) {
    expect(browser.getCurrentUrl(), equals(url));
    return browser;
  }

  @override
  Browser assertPathIs(String path) {
    final url = browser.getCurrentUrl();
    expect(Uri.parse(url).path, equals(path));
    return browser;
  }

  @override
  Browser assertPathBeginsWith(String path) {
    final url = browser.getCurrentUrl();
    expect(Uri.parse(url).path, startsWith(path));
    return browser;
  }

  @override
  Browser assertPathEndsWith(String path) {
    final url = browser.getCurrentUrl();
    expect(Uri.parse(url).path, endsWith(path));
    return browser;
  }

  @override
  Browser assertQueryStringHas(String name, [String? value]) {
    final url = browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, contains(name));
    if (value != null) {
      expect(params[name], equals(value));
    }
    return browser;
  }

  @override
  Browser assertQueryStringMissing(String name) {
    final url = browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, isNot(contains(name)));
    return browser;
  }

  @override
  Browser assertSee(String text) {
    expect(browser.getPageSource(), contains(text));
    return browser;
  }

  @override
  Browser assertDontSee(String text) {
    expect(browser.getPageSource(), isNot(contains(text)));
    return browser;
  }

  @override
  Browser assertSeeIn(String selector, String text) {
    final element = browser.findElement(selector);
    expect(element.text, contains(text));
    return browser;
  }

  @override
  Browser assertDontSeeIn(String selector, String text) {
    final element = browser.findElement(selector);
    expect(element.text, isNot(contains(text)));
    return browser;
  }

  @override
  Browser assertSeeAnythingIn(String selector) {
    final element = browser.findElement(selector);
    expect(element.text.trim(), isNotEmpty);
    return browser;
  }

  @override
  Browser assertSeeNothingIn(String selector) {
    final element = browser.findElement(selector);
    expect(element.text.trim(), isEmpty);
    return browser;
  }

  @override
  Browser assertPresent(String selector) {
    expect(browser.isPresent(selector), isTrue);
    return browser;
  }

  @override
  Browser assertNotPresent(String selector) {
    expect(browser.isPresent(selector), isFalse);
    return browser;
  }

  @override
  Browser assertVisible(String selector) {
    final element = browser.findElement(selector);
    expect(element.displayed, isTrue);
    return browser;
  }

  @override
  Browser assertMissing(String selector) {
    expect(browser.isPresent(selector), isFalse);
    return browser;
  }

  @override
  Browser assertInputPresent(String name) {
    expect(browser.isPresent('input[name="$name"]'), isTrue);
    return browser;
  }

  @override
  Browser assertInputMissing(String name) {
    expect(browser.isPresent('input[name="$name"]'), isFalse);
    return browser;
  }

  @override
  Browser assertInputValue(String field, String value) {
    final element = browser.findElement(field);
    expect(element.attributes['value'], equals(value));
    return browser;
  }

  @override
  Browser assertInputValueIsNot(String field, String value) {
    final element = browser.findElement(field);
    expect(element.attributes['value'], isNot(equals(value)));
    return browser;
  }

  @override
  Browser assertChecked(String field) {
    final element = browser.findElement(field);
    expect(element.selected, isTrue);
    return browser;
  }

  @override
  Browser assertNotChecked(String field) {
    final element = browser.findElement(field);
    expect(element.selected, isFalse);
    return browser;
  }

  @override
  Browser assertRadioSelected(String field, String value) {
    final element = browser
        .findElement('input[type="radio"][name="$field"][value="$value"]');
    expect(element.selected, isTrue);
    return browser;
  }

  @override
  Browser assertRadioNotSelected(String field, String value) {
    final element = browser
        .findElement('input[type="radio"][name="$field"][value="$value"]');
    expect(element.selected, isFalse);
    return browser;
  }

  @override
  Browser assertSelected(String field, String value) {
    final element = browser.findElement('$field option[value="$value"]');
    expect(element.selected, isTrue);
    return browser;
  }

  @override
  Browser assertNotSelected(String field, String value) {
    final element = browser.findElement('$field option[value="$value"]');
    expect(element.selected, isFalse);
    return browser;
  }

  @override
  Browser assertEnabled(String field) {
    final element = browser.findElement(field);
    expect(element.enabled, isTrue);
    return browser;
  }

  @override
  Browser assertDisabled(String field) {
    final element = browser.findElement(field);
    expect(element.enabled, isFalse);
    return browser;
  }

  @override
  Browser assertFocused(String field) {
    final element = browser.findElement(field);
    final activeElement = browser.driver.activeElement;
    if (activeElement == null) {
      fail('No active element found');
    }
    expect(element.equals(activeElement), isTrue);
    return browser;
  }

  @override
  Browser assertNotFocused(String field) {
    final element = browser.findElement(field);
    final activeElement = browser.driver.activeElement;
    if (activeElement == null) return browser;
    expect(element.equals(activeElement), isFalse);
    return browser;
  }

  @override
  Browser assertAuthenticated([String? guard]) {
    // Implementation depends on your authentication setup
    return browser;
  }

  @override
  Browser assertGuest([String? guard]) {
    // Implementation depends on your authentication setup
    return browser;
  }
}
