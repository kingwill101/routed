/// Browser testing components for automated end-to-end tests.
///
/// Provides a unified API for browser automation, page object pattern 
/// implementation, and browser configuration. This library abstracts
/// WebDriver implementations to make writing browser tests simpler and
/// more maintainable.
///
/// These exports include:
/// - Browser configuration and management
/// - Testing utilities
/// - Page object pattern support
/// - WebDriver abstractions
library;

/// Browser bootstrap and configuration
export 'bootstrap/bootstrap.dart';
export 'bootstrap/proxy.dart';
export 'browser_config.dart';

/// Browser testing utilities
export 'browser_test.dart';

/// Page object pattern support
export 'component.dart';

/// Browser factory and interfaces
export 'factory.dart';
export 'interfaces/browser.dart';
export 'page.dart';
