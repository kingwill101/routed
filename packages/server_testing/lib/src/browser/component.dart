import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

/// Represents a reusable UI component within a web page, forming part of the Page Object Pattern.
///
/// A reusable UI element in the page object pattern.
///
/// Encapsulates a specific UI component on a web page such as a navigation menu,
/// modal dialog, or form. Provides an abstraction layer for element selectors
/// and interactions.
///
/// ```dart
/// class NavMenu extends Component {
///   NavMenu(Browser browser) : super(browser, 'nav.main-menu');
///
///   Future<void> clickHomeLink() async {
///     await browser.click('$selector a.home-link');
///   }
///
///   Future<void> openUserMenu() async {
///     await browser.click('$selector .user-dropdown');
///   }
/// }
/// ```
///
/// Use with [Page] objects to organize browser tests using the page object pattern.
///
/// Components encapsulate the structure and interaction logic for a distinct
/// part of a page, such as a login form, navigation menu, or modal dialog.
/// They provide a higher level of abstraction over raw element selectors and
/// browser actions, making tests more readable and maintainable.
///
/// Subclasses should define specific selectors and methods relevant to the
/// component they represent.
///
/// ### Example
///
/// ```dart
/// class SearchWidget extends Component {
///   SearchWidget(Browser browser, String parentSelector)
///       : super(browser, '$parentSelector .search-widget'); // Root element selector
///
///   // Selectors relative to the component's root
///   String get _input => '$selector input[type="search"]';
///   String get _submitButton => '$selector button.search-button';
///
///   // Component-specific actions
///   Future<void> searchFor(String term) async {
///     await browser.type(_input, term);
///     await browser.click(_submitButton);
///   }
///
///   Future<String> readInputValue() async {
///     final element = await browser.findElement(_input);
///     return await element.attributes['value'] ?? '';
///   }
/// }
/// ```
///
/// Components are typically used within [Page] objects.
abstract class Component {
  /// The browser instance for interacting with the page.
  final Browser browser;

  /// The CSS selector that identifies this component in the DOM.
  final String selector;

  /// Creates a new component with the given browser and selector.
  ///
  /// The [browser] is used for page interactions.
  /// The [selector] identifies this component in the DOM.
  Component(this.browser, this.selector);

  /// Finds the root DOM element for this component using its [selector].
  ///
  /// Finds the DOM element representing this component.
  ///
  /// Returns a WebElement or equivalent, depending on the browser implementation.
  Future<dynamic> findElement() async {
    return await browser.findElement(selector);
  }

  /// Asserts that the root element of this component is present and visible on the page.
  ///
  /// Asserts that the component is visible on the page.
  ///
  /// Throws a [TestFailure] if the component is not visible.
  Future<void> assertVisible() async {
    final element = await findElement();
    if (!(element != null && (await element!.displayed) as bool)) {
      throw TestFailure('Component is not visible: $selector');
    }
  }

  /// Asserts that the root element of this component is either not present or not visible on the page.
  ///
  /// Asserts that the component is hidden on the page.
  ///
  /// Throws a [TestFailure] if the component is visible.
  Future<void> assertHidden() async {
    final element = await findElement();
    if (!(element != null && (await element!.displayed) as bool)) {
      throw TestFailure('Component is visible but should be hidden: $selector');
    }
  }
}
