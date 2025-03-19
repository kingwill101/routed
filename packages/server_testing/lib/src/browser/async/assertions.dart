import 'package:test/test.dart';

import '../interfaces/assertions.dart';
import '../interfaces/browser.dart';
import 'browser.dart' show AsyncBrowser;

mixin AsyncBrowserAssertions implements BrowserAssertions {
  AsyncBrowser get browser => this as AsyncBrowser;

  @override
  Future<Browser> assertTitle(String title) async {
    expect(await browser.getTitle(), equals(title));
    return browser;
  }

  @override
  Future<Browser> assertTitleContains(String text) async {
    expect(await browser.getTitle(), contains(text));
    return browser;
  }

  @override
  Future<Browser> assertUrlIs(String url) async {
    expect(await browser.getCurrentUrl(), equals(url));
    return browser;
  }

  @override
  Future<Browser> assertPathIs(String path) async {
    final url = await browser.getCurrentUrl();
    expect(Uri.parse(url).path, equals(path));
    return browser;
  }

  @override
  Future<Browser> assertPathBeginsWith(String path) async {
    final url = await browser.getCurrentUrl();
    expect(Uri.parse(url).path, startsWith(path));
    return browser;
  }

  @override
  Future<Browser> assertPathEndsWith(String path) async {
    final url = await browser.getCurrentUrl();
    expect(Uri.parse(url).path, endsWith(path));
    return browser;
  }

  @override
  Future<Browser> assertQueryStringHas(String name, [String? value]) async {
    final url = await browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, contains(name));
    if (value != null) {
      expect(params[name], equals(value));
    }
    return browser;
  }

  @override
  Future<Browser> assertQueryStringMissing(String name) async {
    final url = await browser.getCurrentUrl();
    final params = Uri.parse(url).queryParameters;
    expect(params, isNot(contains(name)));
    return browser;
  }

  @override
  Future<Browser> assertSee(String text) async {
    expect(await browser.getPageSource(), contains(text));
    return browser;
  }

  @override
  Future<Browser> assertDontSee(String text) async {
    expect(await browser.getPageSource(), isNot(contains(text)));
    return browser;
  }

  @override
  Future<Browser> assertSeeIn(String selector, String text) async {
    final element = await browser.findElement(selector);
    final elementText = await element.text;
    expect(elementText, contains(text));
    return browser;
  }

  @override
  Future<Browser> assertDontSeeIn(String selector, String text) async {
    final element = await browser.findElement(selector);
    final elementText = await element.text;
    expect(elementText, isNot(contains(text)));
    return browser;
  }

  @override
  Future<Browser> assertSeeAnythingIn(String selector) async {
    final element = await browser.findElement(selector);
    final text = await element.text;
    expect(text.trim(), isNotEmpty);
    return browser;
  }

  @override
  Future<Browser> assertSeeNothingIn(String selector) async {
    final element = await browser.findElement(selector);
    final text = await element.text;
    expect(text.trim(), isEmpty);
    return browser;
  }

  @override
  Future<Browser> assertPresent(String selector) async {
    expect(await browser.isPresent(selector), isTrue);
    return browser;
  }

  @override
  Future<Browser> assertNotPresent(String selector) async {
    expect(await browser.isPresent(selector), isFalse);
    return browser;
  }

  @override
  Future<Browser> assertVisible(String selector) async {
    final element = await browser.findElement(selector);
    expect(await element.displayed, isTrue);
    return browser;
  }

  @override
  Future<Browser> assertMissing(String selector) async {
    expect(await browser.isPresent(selector), isFalse);
    return browser;
  }

  @override
  Future<Browser> assertInputPresent(String name) async {
    expect(await browser.isPresent('input[name="$name"]'), isTrue);
    return browser;
  }

  @override
  Future<Browser> assertInputMissing(String name) async {
    expect(await browser.isPresent('input[name="$name"]'), isFalse);
    return browser;
  }

  @override
  Future<Browser> assertInputValue(String field, String value) async {
    final element = await browser.findElement(field);
    expect(await element.attributes['value'], equals(value));
    return browser;
  }

  @override
  Future<Browser> assertInputValueIsNot(String field, String value) async {
    final element = await browser.findElement(field);
    expect(await element.attributes['value'], isNot(equals(value)));
    return browser;
  }

  @override
  Future<Browser> assertChecked(String field) async {
    final element = await browser.findElement(field);
    expect(await element.selected, isTrue);
    return browser;
  }

  @override
  Future<Browser> assertNotChecked(String field) async {
    final element = await browser.findElement(field);
    expect(await element.selected, isFalse);
    return browser;
  }

  @override
  Future<Browser> assertRadioSelected(String field, String value) async {
    final element = await browser
        .findElement('input[type="radio"][name="$field"][value="$value"]');
    expect(await element.selected, isTrue);
    return browser;
  }

  @override
  Future<Browser> assertRadioNotSelected(String field, String value) async {
    final element = await browser
        .findElement('input[type="radio"][name="$field"][value="$value"]');
    expect(await element.selected, isFalse);
    return browser;
  }

  @override
  Future<Browser> assertSelected(String field, String value) async {
    final element = await browser.findElement('$field option[value="$value"]');
    expect(await element.selected, isTrue);
    return browser;
  }

  @override
  Future<Browser> assertNotSelected(String field, String value) async {
    final element = await browser.findElement('$field option[value="$value"]');
    expect(await element.selected, isFalse);
    return browser;
  }

  @override
  Future<Browser> assertEnabled(String field) async {
    final element = await browser.findElement(field);
    expect(await element.enabled, isTrue);
    return browser;
  }

  @override
  Future<Browser> assertDisabled(String field) async {
    final element = await browser.findElement(field);
    expect(await element.enabled, isFalse);
    return browser;
  }

  @override
  Future<Browser> assertFocused(String field) async {
    final element = await browser.findElement(field);
    final activeElement = await browser.driver.activeElement;
    expect(await element.equals(activeElement), isTrue);
    return browser;
  }

  @override
  Future<Browser> assertNotFocused(String field) async {
    final element = await browser.findElement(field);
    final activeElement = await browser.driver.activeElement;
    if (activeElement == null) return browser;
    expect(await element.equals(activeElement), isFalse);
    return browser;
  }

  @override
  Future<Browser> assertAuthenticated([String? guard]) async {
    // Implementation depends on your authentication setup
    return browser;
  }

  @override
  Future<Browser> assertGuest([String? guard]) async {
    // Implementation depends on your authentication setup
    return browser;
  }
}
