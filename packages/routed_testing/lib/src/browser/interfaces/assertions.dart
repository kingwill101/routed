import 'dart:async';

import 'browser.dart';

abstract class BrowserAssertions {
  // Title Assertions
  FutureOr<Browser> assertTitle(String title);
  FutureOr<Browser> assertTitleContains(String text);

  // URL Assertions
  FutureOr<Browser> assertUrlIs(String url);
  FutureOr<Browser> assertPathIs(String path);
  FutureOr<Browser> assertPathBeginsWith(String path);
  FutureOr<Browser> assertPathEndsWith(String path);
  FutureOr<Browser> assertQueryStringHas(String name, [String? value]);
  FutureOr<Browser> assertQueryStringMissing(String name);

  // Text Assertions
  FutureOr<Browser> assertSee(String text);
  FutureOr<Browser> assertDontSee(String text);
  FutureOr<Browser> assertSeeIn(String selector, String text);
  FutureOr<Browser> assertDontSeeIn(String selector, String text);
  FutureOr<Browser> assertSeeAnythingIn(String selector);
  FutureOr<Browser> assertSeeNothingIn(String selector);

  // Element Assertions
  FutureOr<Browser> assertPresent(String selector);
  FutureOr<Browser> assertNotPresent(String selector);
  FutureOr<Browser> assertVisible(String selector);
  FutureOr<Browser> assertMissing(String selector);
  FutureOr<Browser> assertInputPresent(String name);
  FutureOr<Browser> assertInputMissing(String name);

  // Form Assertions
  FutureOr<Browser> assertInputValue(String field, String value);
  FutureOr<Browser> assertInputValueIsNot(String field, String value);
  FutureOr<Browser> assertChecked(String field);
  FutureOr<Browser> assertNotChecked(String field);
  FutureOr<Browser> assertRadioSelected(String field, String value);
  FutureOr<Browser> assertRadioNotSelected(String field, String value);
  FutureOr<Browser> assertSelected(String field, String value);
  FutureOr<Browser> assertNotSelected(String field, String value);

  // State Assertions
  FutureOr<Browser> assertEnabled(String field);
  FutureOr<Browser> assertDisabled(String field);
  FutureOr<Browser> assertFocused(String field);
  FutureOr<Browser> assertNotFocused(String field);

  // Auth Assertions
  FutureOr<Browser> assertAuthenticated([String? guard]);
  FutureOr<Browser> assertGuest([String? guard]);
}
