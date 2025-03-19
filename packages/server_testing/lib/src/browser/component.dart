import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

/// Base class for UI components in the page object pattern.
///
/// A Component represents a reusable UI element on a web page, such as a
/// navigation menu, modal dialog, or form. Components encapsulate the
/// selector logic and user interactions specific to that element.
///
/// Components can be used alongside [Page] objects to organize browser tests
/// using the page object pattern.
///
/// Example:
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
abstract class Component {
  /// The browser instance for interacting with the page.
  final Browser browser;

  /// The CSS selector that identifies this component in the DOM.
  final String selector;

  /// Creates a new component with the specified browser and selector.
  ///
  /// [browser] is the browser instance to use for interactions.
  /// [selector] is the CSS selector that identifies this component.
  Component(this.browser, this.selector);

  /// Finds the DOM element that represents this component.
  ///
  /// Returns the element as a WebElement or equivalent, depending on
  /// the browser implementation.
  Future<dynamic> findElement() async {
    return await browser.findElement(selector);
  }

  /// Asserts that the component is visible on the page.
  ///
  /// Throws a [TestFailure] if the component is not visible.
  Future<void> assertVisible() async {
    final element = await findElement();
    if (!await element.displayed) {
      throw TestFailure('Component is not visible: $selector');
    }
  }

  /// Asserts that the component is hidden on the page.
  ///
  /// Throws a [TestFailure] if the component is visible.
  Future<void> assertHidden() async {
    final element = await findElement();
    if (await element.displayed) {
      throw TestFailure('Component is visible but should be hidden: $selector');
    }
  }
}
