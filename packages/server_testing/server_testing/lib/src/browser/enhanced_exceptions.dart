import 'browser_exception.dart';

/// An enhanced browser exception that provides additional context about failed operations.
///
/// This exception extends [BrowserException] to include more detailed information
/// about the context in which the error occurred, including the selector being used,
/// the action being performed, and optionally a screenshot path for debugging.
///
/// This enhanced exception is particularly useful for debugging browser test failures
/// as it provides more context than the basic [BrowserException].
///
/// Example:
/// ```dart
/// throw EnhancedBrowserException(
///   'Element not found',
///   selector: '#submit-button',
///   action: 'click',
///   screenshotPath: 'test_screenshots/failure_123.png',
/// );
/// ```
class EnhancedBrowserException extends BrowserException {
  /// The CSS selector or element identifier that was being used when the error occurred.
  final String? selector;

  /// The action that was being performed when the error occurred (e.g., 'click', 'type', 'wait').
  final String? action;

  /// The path to a screenshot captured when the error occurred, if available.
  final String? screenshotPath;

  /// Additional details about the error context.
  final String? details;

  /// Creates an [EnhancedBrowserException] with additional context information.
  ///
  /// The [message] describes the error that occurred.
  /// The [selector] is the CSS selector or element identifier being used.
  /// The [action] is the operation being performed (e.g., 'click', 'type').
  /// The [screenshotPath] is the path to a screenshot captured during the error.
  /// The [details] provides additional context about the error.
  /// The [cause] is the underlying exception that caused this error, if any.
  EnhancedBrowserException(
    String message, {
    this.selector,
    this.action,
    this.screenshotPath,
    this.details,
    dynamic cause,
  }) : super(message, cause);

  /// Returns a detailed string representation of the exception including all context information.
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('EnhancedBrowserException: $message');

    if (action != null) {
      buffer.write('\n  Action: $action');
    }

    if (selector != null) {
      buffer.write('\n  Selector: $selector');
    }

    if (details != null) {
      buffer.write('\n  Details: $details');
    }

    if (screenshotPath != null) {
      buffer.write('\n  Screenshot: $screenshotPath');
    }

    if (cause != null) {
      buffer.write('\n  Cause: $cause');
    }

    return buffer.toString();
  }

  /// Creates a copy of this exception with updated context information.
  ///
  /// This is useful for adding additional context as the exception propagates
  /// through different layers of the browser automation system.
  EnhancedBrowserException copyWith({
    String? message,
    String? selector,
    String? action,
    String? screenshotPath,
    String? details,
    dynamic cause,
  }) {
    return EnhancedBrowserException(
      message ?? this.message,
      selector: selector ?? this.selector,
      action: action ?? this.action,
      screenshotPath: screenshotPath ?? this.screenshotPath,
      details: details ?? this.details,
      cause: cause ?? this.cause,
    );
  }
}

/// An enhanced timeout exception that provides additional context about timeout failures.
///
/// This exception extends [TimeoutException] to include more detailed information
/// about what was being waited for and the context of the timeout.
class EnhancedTimeoutException extends TimeoutException {
  /// The CSS selector or element identifier that was being waited for.
  final String? selector;

  /// The action that was being performed when the timeout occurred.
  final String? action;

  /// The path to a screenshot captured when the timeout occurred, if available.
  final String? screenshotPath;

  /// Additional details about the timeout context.
  final String? details;

  /// Creates an [EnhancedTimeoutException] with additional context information.
  ///
  /// The [message] describes the timeout that occurred.
  /// The [timeout] is the duration that was exceeded.
  /// The [selector] is the CSS selector or element identifier being waited for.
  /// The [action] is the operation being performed (e.g., 'waitForElement', 'waitForText').
  /// The [screenshotPath] is the path to a screenshot captured during the timeout.
  /// The [details] provides additional context about the timeout.
  EnhancedTimeoutException(
    String message, {
    Duration? timeout,
    this.selector,
    this.action,
    this.screenshotPath,
    this.details,
  }) : super(message, timeout);

  /// Returns a detailed string representation of the timeout exception including all context information.
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('EnhancedTimeoutException: $message');

    if (timeout != null) {
      buffer.write(' (${timeout!.inSeconds}s)');
    }

    if (action != null) {
      buffer.write('\n  Action: $action');
    }

    if (selector != null) {
      buffer.write('\n  Selector: $selector');
    }

    if (details != null) {
      buffer.write('\n  Details: $details');
    }

    if (screenshotPath != null) {
      buffer.write('\n  Screenshot: $screenshotPath');
    }

    return buffer.toString();
  }
}
