import 'package:server_testing/src/browser/interfaces/browser.dart';
import 'package:test/test.dart';

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

  /// Finds the DOM element representing this component.
  ///
  /// Returns a WebElement or equivalent, depending on the browser implementation.
  Future<dynamic> findElement() async {
    return await browser.findElement(selector);
  }

  /// Asserts that the component is visible on the page.
  ///
  /// Throws a [TestFailure] if the component is not visible.
  Future<void> assertVisible() async {
    final element = await findElement();
    if (!(element != null && (await element!.displayed) as bool)) {
      throw TestFailure('Component is not visible: $selector');
    }
  }

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
