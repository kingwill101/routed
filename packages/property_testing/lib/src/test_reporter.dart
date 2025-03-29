import 'dart:convert';

import 'property_test_runner.dart';

/// A reporter for property test results
/// Provides static methods for formatting [PropertyResult] objects into
/// human-readable reports.
///
/// The [formatResult] method generates a detailed string summarizing the test
/// outcome, including pass/fail status, number of tests run, failing inputs
/// (original and shrunk), error details, and stack traces for failures.
///
/// ```dart
/// // Assuming 'result' is a PropertyResult from PropertyTestRunner.run()
/// print(PropertyTestReporter.formatResult(result));
///
/// // Or using the extension method:
/// print(result.report);
/// ```
class PropertyTestReporter {
  /// Format a test result into a detailed report
  static String formatResult(PropertyResult result) {
    final buffer = StringBuffer();

    if (result.success) {
      buffer.writeln('✓ Property test passed');
      buffer.writeln('  ${result.numTests} test cases passed');
    } else {
      buffer.writeln('✗ Property test failed');
      buffer.writeln('  Failed after ${result.numTests} test cases');

      if (result.originalFailingInput != null) {
        buffer.writeln('\nOriginal failing input:');
        buffer.writeln(_formatValue(result.originalFailingInput));
      }

      if (result.failingInput != null) {
        buffer.writeln(
            '\nMinimal failing input (after ${result.numShrinks} shrinks):');
        buffer.writeln(_formatValue(result.failingInput));
      }

      if (result.error != null) {
        buffer.writeln('\nError:');
        buffer.writeln('  ${result.error}');
      }

      if (result.stackTrace != null) {
        buffer.writeln('\nStack trace:');
        buffer.writeln(_formatStackTrace(result.stackTrace!));
      }
    }

    return buffer.toString();
  }

  /// Format a value for display
  static String _formatValue(dynamic value) {
    if (value == null) return 'null';

    try {
      // Try to encode as JSON for structured display
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      // Fall back to toString() if JSON encoding fails
      final str = value.toString();
      if (str.contains('\n')) {
        // Indent multiline strings
        return str.split('\n').map((line) => '  $line').join('\n');
      }
      return '  $str';
    }
  }

  /// Format a stack trace for display
  static String _formatStackTrace(StackTrace stackTrace) {
    return stackTrace
        .toString()
        .split('\n')
        .map((line) => '  $line')
        .join('\n');
  }
}

/// Extension methods for working with test results
/// Extension methods for [PropertyResult] providing convenience accessors.
extension PropertyResultExtensions on PropertyResult {
  /// Get a detailed report of this test result
  String get report => PropertyTestReporter.formatResult(this);
}

/// A collector for test statistics across multiple runs
/// Collects and summarizes statistics across multiple property test runs.
///
/// Tracks total tests, passed/failed counts, total shrinks performed, and
/// total execution duration. The [recordResult] method updates the statistics
/// with the outcome of a single test run. The [getSummary] method provides
/// a formatted string report of the aggregated statistics.
///
/// ```dart
/// final collector = TestStatisticsCollector();
/// final stopwatch = Stopwatch();
///
/// for (int i = 0; i < 10; i++) {
///   final runner = PropertyTestRunner(/* ... */);
///   stopwatch.start();
///   final result = await runner.run();
///   stopwatch.stop();
///   collector.recordResult(result, stopwatch.elapsed);
///   stopwatch.reset();
/// }
///
/// print(collector.getSummary());
/// ```
class TestStatisticsCollector {
  int _totalTests = 0;
  int _passedTests = 0;
  int _failedTests = 0;
  int _totalShrinks = 0;
  Duration _totalDuration = Duration.zero;
  final List<PropertyResult> _failedResults = [];

  /// Record a test result
  void recordResult(PropertyResult result, Duration duration) {
    _totalTests++;
    _totalDuration += duration;

    if (result.success) {
      _passedTests++;
    } else {
      _failedTests++;
      _totalShrinks += result.numShrinks;
      _failedResults.add(result);
    }
  }

  /// Get a summary of all recorded test results
  String getSummary() {
    final buffer = StringBuffer();

    buffer.writeln('Test Statistics:');
    buffer.writeln('  Total tests: $_totalTests');
    buffer.writeln('  Passed: $_passedTests');
    buffer.writeln('  Failed: $_failedTests');

    if (_totalTests > 0) {
      final successRate = (_passedTests / _totalTests * 100).toStringAsFixed(1);
      buffer.writeln('  Success rate: $successRate%');
    }

    if (_failedTests > 0) {
      buffer.writeln('  Total shrinks: $_totalShrinks');
      buffer.writeln(
          '  Average shrinks per failure: ${(_totalShrinks / _failedTests).toStringAsFixed(1)}');
    }

    final avgDuration =
        _totalTests > 0 ? _totalDuration ~/ _totalTests : Duration.zero;
    buffer.writeln('  Average test duration: ${_formatDuration(avgDuration)}');

    if (_failedResults.isNotEmpty) {
      buffer.writeln('\nFailed Test Details:');
      for (var i = 0; i < _failedResults.length; i++) {
        buffer.writeln('\nFailure #${i + 1}:');
        buffer.writeln(_failedResults[i].report);
      }
    }

    return buffer.toString();
  }

  static String _formatDuration(Duration d) {
    if (d.inMicroseconds < 1000) {
      return '${d.inMicroseconds}µs';
    } else if (d.inMilliseconds < 1000) {
      return '${d.inMilliseconds}ms';
    } else {
      return '${d.inSeconds}s';
    }
  }
}
