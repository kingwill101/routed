import 'dart:io';

/// A logger for browser operations that supports verbose logging and debugging.
///
/// This logger provides structured logging for browser interactions, with support
/// for different log levels and optional verbose output. It's designed to help
/// debug browser test failures and understand the sequence of operations.
class EnhancedBrowserLogger {
  /// Whether verbose logging is enabled.
  final bool verboseLogging;

  /// The directory where log files should be written, if any.
  final String? logDirectory;

  /// Creates a new [EnhancedBrowserLogger] instance.
  ///
  /// If [verboseLogging] is true, detailed operation logs will be output.
  /// If [logDirectory] is provided, logs will also be written to files in that directory.
  const EnhancedBrowserLogger({this.verboseLogging = false, this.logDirectory});

  /// Logs an informational message about a browser operation.
  ///
  /// The [action] describes what operation is being performed.
  /// The [selector] is the CSS selector being used, if applicable.
  /// The [details] provides additional context about the operation.
  void logInfo(
    String message, {
    String? action,
    String? selector,
    String? details,
  }) {
    if (!verboseLogging) return;

    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.write('[$timestamp] INFO: $message');

    if (action != null) {
      buffer.write(' (action: $action)');
    }

    if (selector != null) {
      buffer.write(' (selector: $selector)');
    }

    if (details != null) {
      buffer.write(' - $details');
    }

    final logMessage = buffer.toString();
    print(logMessage);

    _writeToFile(logMessage);
  }

  /// Logs a warning message about a browser operation.
  ///
  /// Warnings are always logged regardless of the verbose setting, as they
  /// indicate potential issues that should be visible to developers.
  void logWarning(
    String message, {
    String? action,
    String? selector,
    String? details,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.write('[$timestamp] WARNING: $message');

    if (action != null) {
      buffer.write(' (action: $action)');
    }

    if (selector != null) {
      buffer.write(' (selector: $selector)');
    }

    if (details != null) {
      buffer.write(' - $details');
    }

    final logMessage = buffer.toString();
    print(logMessage);

    _writeToFile(logMessage);
  }

  /// Logs an error message about a browser operation.
  ///
  /// Errors are always logged regardless of the verbose setting.
  void logError(
    String message, {
    String? action,
    String? selector,
    String? details,
    dynamic error,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.write('[$timestamp] ERROR: $message');

    if (action != null) {
      buffer.write(' (action: $action)');
    }

    if (selector != null) {
      buffer.write(' (selector: $selector)');
    }

    if (details != null) {
      buffer.write(' - $details');
    }

    if (error != null) {
      buffer.write('\n  Underlying error: $error');
    }

    final logMessage = buffer.toString();
    print(logMessage);

    _writeToFile(logMessage);
  }

  /// Logs the start of a browser operation.
  ///
  /// This is useful for tracking the sequence of operations in verbose mode.
  void logOperationStart(
    String action, {
    String? selector,
    Map<String, dynamic>? parameters,
  }) {
    if (!verboseLogging) return;

    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.write('[$timestamp] START: $action');

    if (selector != null) {
      buffer.write(' on $selector');
    }

    if (parameters != null && parameters.isNotEmpty) {
      buffer.write(' with parameters: $parameters');
    }

    final logMessage = buffer.toString();
    print(logMessage);

    _writeToFile(logMessage);
  }

  /// Logs the completion of a browser operation.
  ///
  /// This is useful for tracking the sequence of operations in verbose mode.
  void logOperationComplete(
    String action, {
    String? selector,
    Duration? duration,
  }) {
    if (!verboseLogging) return;

    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.write('[$timestamp] COMPLETE: $action');

    if (selector != null) {
      buffer.write(' on $selector');
    }

    if (duration != null) {
      buffer.write(' (took ${duration.inMilliseconds}ms)');
    }

    final logMessage = buffer.toString();
    print(logMessage);

    _writeToFile(logMessage);
  }

  /// Writes a log message to a file if a log directory is configured.
  void _writeToFile(String message) {
    if (logDirectory == null) return;

    try {
      final logDir = Directory(logDirectory!);
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final logFile = File('${logDirectory!}/browser_test_$dateStr.log');

      logFile.writeAsStringSync('$message\n', mode: FileMode.append);
    } catch (e) {
      // Don't let logging errors break the tests
      print('Warning: Failed to write to log file: $e');
    }
  }
}
