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
export 'bootstrap/browser_paths.dart' show BrowserPaths;
export 'browser_config.dart';
export 'browser_logger.dart' show EnhancedBrowserLogger;
export 'browser_management.dart' show BrowserManagement;
export 'browser_exception.dart';
export 'logger.dart' show BrowserLogger;

/// Browser testing utilities
export 'browser_test.dart';

/// Page object pattern support
export 'browser_types/chromium.dart';
export 'browser_types/firefox.dart';
export 'component.dart';

/// Enhanced error handling and debugging
export 'enhanced_exceptions.dart';

/// Browser factory and interfaces
export 'factory.dart';
export 'interfaces/browser.dart';
export 'page.dart';
export 'screenshot_manager.dart';
