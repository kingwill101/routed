import 'dart:convert';
import 'dart:io';

import 'package:contextual/contextual.dart';
import 'package:path/path.dart' as path;

/// Structured logger used by the browser bootstrap code.
///
/// Wraps the `contextual` logger to provide contextual logging, optional
/// persistence, and test-scoped metadata while allowing output to be disabled
/// entirely in noisy CI environments.
class BrowserLogger {
  static bool defaultEnabled() {
    final enable = Platform.environment['SERVER_TESTING_ENABLE_LOGS'];
    if (enable != null) {
      if (_isTruthy(enable)) return true;
      if (_isFalsy(enable)) return false;
    }

    final disable = Platform.environment['SERVER_TESTING_DISABLE_LOGS'];
    if (disable != null && _isTruthy(disable)) {
      return false;
    }

    return true;
  }

  static bool _isTruthy(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  static bool _isFalsy(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '0' ||
        normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'off';
  }

  final String logDir;
  final bool _verbose;
  final bool _enabled;
  final Logger? _logger;

  final StringBuffer _memoryLog = StringBuffer();
  final DateTime _startTime = DateTime.now();

  Context _baseContext = Context();
  String? _currentTestName;

  BrowserLogger({
    this.logDir = 'test/logs',
    bool verbose = false,
    bool? enabled,
  })  : _verbose = verbose,
        _enabled = enabled ?? BrowserLogger.defaultEnabled(),
        _logger = (enabled ?? BrowserLogger.defaultEnabled())
            ? (Logger(
              environment: verbose ? 'development' : 'test',
              formatter:
                  verbose ? PrettyLogFormatter() : PlainTextLogFormatter(),
            )
              ..addChannel('console', ConsoleLogDriver()))
            : null {
    if (_enabled) {
      final fileDriver = DailyFileLogDriver(
        path.join(logDir, 'server_testing'),
        retentionDays: 7,
        flushInterval: const Duration(seconds: 1),
      );
      _logger?.addChannel('file', fileDriver);
    }
  }

  void startTestLog(String testName) {
    if (!_enabled) return;

    _currentTestName = testName;
    _setBaseContext(Context({'test': testName}));
    info('Starting test: $testName');
    _writeMetadata();
  }

  Future<void> endTestLog() async {
    if (!_enabled) return;

    if (_currentTestName != null) {
      info('Completed test: $_currentTestName');
    }

    _currentTestName = null;
    _setBaseContext(Context());
  }

  void info(String message, {Context? context}) {
    if (!_enabled) return;

    _memoryLog.writeln(_format('INFO', message));
    _logger?.info(message, _mergeContext(context));
  }

  void debug(String message, {StackTrace? stackTrace, Context? context}) {
    if (!_enabled || !_verbose) return;

    final merged = _mergeContext(context);
    if (stackTrace != null) {
      merged.add('stackTrace', stackTrace.toString());
    }

    _memoryLog.writeln(_format('DEBUG', message));
    _logger?.debug(message, merged);
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Context? context,
  }) {
    if (!_enabled) return;

    final merged = _mergeContext(context);
    if (error != null) {
      merged.add('error', error.toString());
    }
    if (stackTrace != null) {
      merged.add('stackTrace', stackTrace.toString());
    }

    _memoryLog.writeln(_format('ERROR', message));
    _logger?.error(message, merged);
  }

  Future<void> saveTestReport(String testName) async {
    if (!_enabled) return;

    final dir = Directory(logDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final sanitized = _sanitize(testName);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final reportPath = path.join(
      dir.path,
      '${sanitized}_report_$timestamp.txt',
    );

    final report = StringBuffer()
      ..writeln('Test Report: $testName')
      ..writeln('Timestamp: ${DateTime.now()}')
      ..writeln('Duration: ${DateTime.now().difference(_startTime)}')
      ..writeln('---')
      ..writeln(_memoryLog.toString());

    await File(reportPath).writeAsString(report.toString());
  }

  Future<void> saveBrowserLogs(
    String testName,
    List<Map<String, dynamic>> logs,
  ) async {
    if (!_enabled) return;

    final dir = Directory(logDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final sanitized = _sanitize(testName);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final logPath = path.join(dir.path, '${sanitized}_browser_$timestamp.json');

    final payload = {'timestamp': timestamp, 'test': testName, 'logs': logs};

    await File(
      logPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  Future<void> dispose() async {
    if (!_enabled) return;

    await _logger?.shutdown();
    _memoryLog.clear();
  }

  void _writeMetadata() {
    info('Test Environment:');
    info(
      '  Platform: ${Platform.operatingSystem}'
      ' ${Platform.operatingSystemVersion}',
    );
    info('  Dart: ${Platform.version}');
    info('  Directory: ${Directory.current.path}');
    info('  PID: $pid');
    info('---');
  }

  void _setBaseContext(Context context) {
    _baseContext = context;
    _logger?.clearSharedContext();
    _logger?.withContext(_baseContext.all());
  }

  Context _mergeContext(Context? context) {
    final merged = Context(_baseContext.all());
    if (context != null) {
      merged.addAll(context.all());
    }
    return merged;
  }

  String _format(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    return '[$timestamp] [$pid] $level: $message';
  }

  String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
}
