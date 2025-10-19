import 'dart:async' show FutureOr;

import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

/// Represents a reusable UI component within a web page, forming part of the Page Object Pattern.
///
/// Encapsulates a specific UI component, providing scoped selectors and
/// ergonomic helpers for interacting with elements inside the component's root.
abstract class Component {
  /// The browser instance for interacting with the page.
  final Browser browser;

  /// The CSS selector that identifies this component's root element in the DOM.
  final String selector;

  /// Creates a new component with the given browser and root [selector].
  Component(this.browser, this.selector);

  /// Returns a selector scoped within this component's root.
  ///
  /// Example: scope('.btn') => '$selector .btn'
  String scope(String subSelector) => '$selector $subSelector';

  /// Finds the root DOM element for this component using its [selector].
  Future<dynamic> findElement() =>
      Future.sync(() => browser.findElement(selector));

  /// Finds a descendant element inside this component using [subSelector].
  Future<dynamic> find(String subSelector) =>
      Future.sync(() => browser.findElement(scope(subSelector)));

  /// Clicks a descendant element inside this component.
  Future<void> click(String subSelector) =>
      Future.sync(() => browser.click(scope(subSelector)));

  /// Types into a descendant element inside this component.
  Future<void> type(String subSelector, String value) =>
      Future.sync(() => browser.type(scope(subSelector), value));

  /// Returns whether this component's root element exists in the DOM.
  Future<bool> isPresent() => Future.sync(() => browser.isPresent(selector));

  /// Asserts that the component's root element is present.
  Future<void> assertPresent() async {
    final present = await isPresent();
    expect(present, isTrue, reason: 'Component not present: $selector');
  }

  /// Reads text content of a descendant element inside this component.
  Future<String> text(String subSelector) async {
    final el = await find(subSelector);
    final t = await el.text;
    return t as String;
  }

  /// Returns whether a descendant element exists within this component.
  Future<bool> exists(String subSelector) =>
      Future.sync(() => browser.isPresent(scope(subSelector)));

  /// Runs multiple actions with a scoping helper for this component.
  Future<T> within<T>(
    FutureOr<T> Function(String Function(String) s) action,
  ) async {
    String s(String sub) => scope(sub);
    return await action(s);
  }

  /// Asserts that the component's root element is not present.
  Future<void> assertNotPresent() async {
    final present = await isPresent();
    expect(
      present,
      isFalse,
      reason: 'Component should not be present: $selector',
    );
  }

  /// Convenience: asserts a descendant exists within this component.
  Future<void> assertHas(String subSelector) async {
    final present = await browser.isPresent(scope(subSelector));
    expect(
      present,
      isTrue,
      reason: 'Expected to find $subSelector within $selector',
    );
  }

  /// Convenience: asserts a descendant does not exist within this component.
  Future<void> assertHasNot(String subSelector) async {
    final present = await browser.isPresent(scope(subSelector));
    expect(
      present,
      isFalse,
      reason: 'Did not expect to find $subSelector within $selector',
    );
  }
}
