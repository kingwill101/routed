import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class BrowserLogger {
  final Directory _logDir;
  final bool _verbose;
  IOSink? _currentTestLog;
  final StringBuffer _memoryLog = StringBuffer();
  final DateTime _testStartTime = DateTime.now();

  BrowserLogger({
    String logDir = 'test/logs',
    bool verbose = false,
  })  : _logDir = Directory(logDir),
        _verbose = verbose {
    if (!_logDir.existsSync()) {
      _logDir.createSync(recursive: true);
    }
  }

  void startTestLog(String testName) {
    final sanitizedName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final logFile =
        File(path.join(_logDir.path, '${sanitizedName}_$timestamp.log'));
    _currentTestLog = logFile.openWrite();
    info('Starting test: $testName');
    _writeMetadata();
  }

  void _writeMetadata() {
    info('Test Environment:');
    info(
        '  Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    info('  Dart: ${Platform.version}');
    info('  Directory: ${Directory.current.path}');
    info('  PID: $pid');
    info('---');
  }

  void info(String message) {
    final entry = _formatLogEntry('INFO', message);
    _write(entry);
  }

  void debug(String message, [StackTrace? stackTrace]) {
    if (_verbose) {
      final entry = _formatLogEntry('DEBUG', message);
      _write(entry);

      if (stackTrace != null) {
        _write(_formatLogEntry('DEBUG', 'Stack trace:\n$stackTrace'));
      }
    }
  }

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

  String _formatLogEntry(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    return '[$timestamp] [$pid] $level: $message';
  }

  void _write(String entry) {
    print(entry);
    _memoryLog.writeln(entry);
    _currentTestLog?.writeln(entry);
  }

  Future<void> endTestLog() async {
    await _currentTestLog?.flush();
    await _currentTestLog?.close();
    _currentTestLog = null;
  }

  Future<void> saveTestReport(String testName) async {
    final sanitizedName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final reportFile =
        File(path.join(_logDir.path, '${sanitizedName}_report_$timestamp.txt'));

    final report = StringBuffer()
      ..writeln('Test Report: $testName')
      ..writeln('Timestamp: ${DateTime.now()}')
      ..writeln('Duration: ${DateTime.now().difference(_testStartTime)}')
      ..writeln('---\n')
      ..writeln('Complete Log:')
      ..writeln(_memoryLog.toString());

    await reportFile.writeAsString(report.toString());
  }

  Future<void> saveBrowserLogs(
      String testName, List<Map<String, dynamic>> logs) async {
    final sanitizedName = testName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final logFile = File(
        path.join(_logDir.path, '${sanitizedName}_browser_$timestamp.json'));

    await logFile.writeAsString(
      JsonEncoder.withIndent('  ').convert({
        'timestamp': timestamp,
        'test': testName,
        'logs': logs,
      }),
    );
  }

  Future<void> dispose() async {
    await endTestLog();
    _memoryLog.clear();
  }
}
