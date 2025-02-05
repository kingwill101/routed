import 'browser.dart';

mixin BrowserAssertions {
  // Title Assertions
  Future<Browser> assertTitle(String title);
  Future<Browser> assertTitleContains(String text);

  // URL Assertions
  Future<Browser> assertUrlIs(String url);
  Future<Browser> assertPathIs(String path);
  Future<Browser> assertPathBeginsWith(String path);
  Future<Browser> assertPathEndsWith(String path);
  Future<Browser> assertQueryStringHas(String name, [String? value]);
  Future<Browser> assertQueryStringMissing(String name);

  // Text Assertions
  Future<Browser> assertSee(String text);
  Future<Browser> assertDontSee(String text);
  Future<Browser> assertSeeIn(String selector, String text);
  Future<Browser> assertDontSeeIn(String selector, String text);
  Future<Browser> assertSeeAnythingIn(String selector);
  Future<Browser> assertSeeNothingIn(String selector);

  // Element Assertions
  Future<Browser> assertPresent(String selector);
  Future<Browser> assertNotPresent(String selector);
  Future<Browser> assertVisible(String selector);
  Future<Browser> assertMissing(String selector);
  Future<Browser> assertInputPresent(String name);
  Future<Browser> assertInputMissing(String name);

  // Form Assertions
  Future<Browser> assertInputValue(String field, String value);
  Future<Browser> assertInputValueIsNot(String field, String value);
  Future<Browser> assertChecked(String field);
  Future<Browser> assertNotChecked(String field);
  Future<Browser> assertRadioSelected(String field, String value);
  Future<Browser> assertRadioNotSelected(String field, String value);
  Future<Browser> assertSelected(String field, String value);
  Future<Browser> assertNotSelected(String field, String value);

  // State Assertions
  Future<Browser> assertEnabled(String field);
  Future<Browser> assertDisabled(String field);
  Future<Browser> assertFocused(String field);
  Future<Browser> assertNotFocused(String field);

  // Auth Assertions
  Future<Browser> assertAuthenticated([String? guard]);
  Future<Browser> assertGuest([String? guard]);

  // Screenshot/Source
  Future<Browser> screenshot(String name);
  Future<Browser> source(String name);
}
