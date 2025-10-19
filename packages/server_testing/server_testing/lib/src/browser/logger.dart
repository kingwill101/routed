import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Provides logging capabilities specifically tailored for browser tests.
///
/// Logging utility for browser tests.
///
/// Creates structured logs for browser tests, including console output,
/// test reports, and browser console logs. Manages log files in the
/// specified directory.
///
/// ```dart
/// final logger = BrowserLogger(logDir: 'test/logs', verbose: true);
/// logger.startTestLog('login_test');
/// logger.info('Starting test');
/// await runTest();
/// logger.info('Test complete');
/// await logger.endTestLog();
/// ```
///
/// This logger facilitates creating structured log files for individual tests,
/// capturing timestamped messages, process ID, log levels (INFO, DEBUG, ERROR),
/// and potentially browser console output or test reports. It helps in
/// debugging failed tests by providing a detailed record of actions and events.
///
/// ### Example
///
/// ```dart
/// // In test setup (e.g., inside testBootstrap or setUpAll)
/// final logger = BrowserLogger(logDir: 'test_logs', verbose: true);
///
/// // Inside a test or test group setup
/// logger.startTestLog('my_feature_test');
/// logger.info('Navigating to homepage...');
/// try {
///   // ... perform test actions ...
///   logger.debug('Intermediate state checked.');
///   // ... more actions ...
///   logger.info('Test completed successfully.');
/// } catch (e, st) {
///   logger.error('Test failed!', e, st);
///   rethrow;
/// } finally {
///   await logger.endTestLog(); // Close the specific test log file
///   // Optionally save full report or browser logs here
///   await logger.saveTestReport('my_feature_test');
/// }
///
/// // In global teardown (e.g., tearDownAll)
/// await logger.dispose(); // Ensure all resources are released
/// ```
class BrowserLogger {
  /// The directory where log files will be created.
  final Directory _logDir;

  /// Whether verbose (DEBUG level) logging is enabled.
  final bool _verbose;

  /// The [IOSink] for the currently active test log file, or `null`.
  IOSink? _currentTestLog;

  /// An in-memory buffer accumulating all log entries for the entire run,
  /// potentially used for generating a final report.
  final StringBuffer _memoryLog = StringBuffer();

  /// The time when the logger instance was created, used for calculating total test duration.
  final DateTime _testStartTime = DateTime.now();

  /// Creates a [BrowserLogger] instance.
  ///
  /// Creates a logger with the specified log directory and verbosity.
  ///
  /// Creates the log directory if it doesn't exist.
  ///
  /// Configures the logger to store files in [logDir] and enables DEBUG level
  /// messages if [verbose] is true. Creates the log directory if it doesn't exist.
  BrowserLogger({String logDir = 'test/logs', bool verbose = false})
    : _logDir = Directory(logDir),
      _verbose = verbose {
    if (!_logDir.existsSync()) {
      _logDir.createSync(recursive: true);
    }
  }

  /// Begins logging for a specific test identified by [testName].
  ///
  /// Starts logging for a test with the given name.
  ///
  /// Creates a log file with the test name and timestamp.
  ///
  /// Creates a uniquely named log file (using [testName] and a timestamp) in
  /// the configured [logDir]. Subsequent log messages will be written to this
  /// file (and the console/memory buffer) until [endTestLog] is called.
  /// Automatically logs initial metadata via [_writeMetadata].
  void startTestLog(String testName) {
    final sanitizedName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final logFile = File(
      path.join(_logDir.path, '${sanitizedName}_$timestamp.log'),
    );
    _currentTestLog = logFile.openWrite();
    info('Starting test: $testName');
    _writeMetadata();
  }

  /// Writes standard environment metadata to the log at the start of a test log.
  void _writeMetadata() {
    info('Test Environment:');
    info(
      '  Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    info('  Dart: ${Platform.version}');
    info('  Directory: ${Directory.current.path}');
    info('  PID: $pid');
    info('---');
  }

  /// Logs an informational [message] at the INFO level.
  /// Logs an informational message.
  void info(String message) {
    final entry = _formatLogEntry('INFO', message);
    _write(entry);
  }

  /// Logs a debug [message] at the DEBUG level.
  ///
  /// Logs a debug message when verbose logging is enabled.
  ///
  /// Includes stack trace if provided.
  ///
  /// The message is only logged if verbose mode ([_verbose]) is enabled during
  /// logger creation. If a [stackTrace] is provided, it is also logged.
  void debug(String message, [StackTrace? stackTrace]) {
    if (_verbose) {
      final entry = _formatLogEntry('DEBUG', message);
      _write(entry);

      if (stackTrace != null) {
        _write(_formatLogEntry('DEBUG', 'Stack trace:\n$stackTrace'));
      }
    }
  }

  /// Logs an error [message] at the ERROR level.
  ///
  /// Logs an error message with optional error object and stack trace.
  ///
  /// Optionally includes the string representation of the [error] object and the
  /// formatted [stackTrace] if provided.
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    final entry = _formatLogEntry('ERROR', message);
    _write(entry);

    if (error != null) {
      _write(_formatLogEntry('ERROR', 'Cause: $error'));
    }

    if (stackTrace != null) {
      _write(_formatLogEntry('ERROR', 'Stack trace:\n$stackTrace'));
    }
  }

  /// Formats a log entry string including timestamp, PID, level, and message.
  String _formatLogEntry(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    return '[$timestamp] [$pid] $level: $message';
  }

  /// Writes a formatted log [entry] to the console, the in-memory buffer,
  /// and the current test log file (if active).
  void _write(String entry) {
    print(entry);
    _memoryLog.writeln(entry);
    _currentTestLog?.writeln(entry);
  }

  /// Finalizes and closes the log file for the currently active test.
  ///
  /// Ends the current test log and closes the log file.
  ///
  /// Flushes any buffered output and closes the [IOSink] associated with the
  /// log file started by [startTestLog]. Should be called at the end of each test.
  Future<void> endTestLog() async {
    await _currentTestLog?.flush();
    await _currentTestLog?.close();
    _currentTestLog = null;
  }

  /// Creates a summary report file for a specific [testName].
  ///
  /// Saves a test report with complete log history.
  ///
  /// The report includes the full log content accumulated in the memory buffer
  /// ([_memoryLog]), along with timestamps and total duration. The report is
  /// saved to a uniquely named file in the [logDir].
  Future<void> saveTestReport(String testName) async {
    final sanitizedName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final reportFile = File(
      path.join(_logDir.path, '${sanitizedName}_report_$timestamp.txt'),
    );

    final report = StringBuffer()
      ..writeln('Test Report: $testName')
      ..writeln('Timestamp: ${DateTime.now()}')
      ..writeln('Duration: ${DateTime.now().difference(_testStartTime)}')
      ..writeln('---\n')
      ..writeln('Complete Log:')
      ..writeln(_memoryLog.toString());

    await reportFile.writeAsString(report.toString());
  }

  /// Saves captured browser console [logs] to a JSON file for a specific [testName].
  ///
  /// Saves browser console logs to a JSON file.
  ///
  /// The [logs] are expected to be a list of structured log entries (e.g., maps
  /// obtained from WebDriver). The file is saved with a unique name in the [logDir].
  Future<void> saveBrowserLogs(String testName,
      List<Map<String, dynamic>> logs,) async {
    final sanitizedName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final logFile = File(
      path.join(_logDir.path, '${sanitizedName}_browser_$timestamp.json'),
    );

    await logFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'timestamp': timestamp, 'test': testName, 'logs': logs}),
    );
  }

  /// Cleans up logger resources.
  ///
  /// Releases resources and closes any open logs.
  ///
  /// Ensures any currently open test log file is closed and clears the in-memory
  /// log buffer. Should be called at the very end of the test suite (e.g., in `tearDownAll`).
  Future<void> dispose() async {
    await endTestLog();
    _memoryLog.clear();
  }
}
