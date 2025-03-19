/// This file exports the public API for browser testing features.
///
/// These exports include:
/// - Browser configuration and management
/// - Testing utilities
/// - Page object pattern support
/// - WebDriver abstractions
library;

/// Browser bootstrap and configuration
export 'bootstrap/bootstrap.dart';
export 'bootstrap/browser_manager.dart';
export 'bootstrap/progress.dart';
export 'bootstrap/proxy.dart';
export 'bootstrap/update_checker.dart';
export 'browser_config.dart';
/// Browser testing utilities
export 'browser_test.dart';
/// Page object pattern support
export 'component.dart';
/// Browser factory and interfaces
export 'factory.dart';
export 'interfaces/browser.dart';
export 'page.dart';
