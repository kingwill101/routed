import 'dart:convert' show base64;
import 'dart:io';

/// Manages screenshot capture for browser tests, including automatic capture on failures.
///
/// This class handles the creation of screenshot directories, generation of unique
/// filenames, and the actual capture and saving of screenshots from WebDriver instances.
class ScreenshotManager {
  /// The directory where screenshots should be saved.
  final String screenshotDirectory;

  /// Whether automatic screenshots are enabled.
  final bool autoScreenshots;

  /// Creates a new [ScreenshotManager] instance.
  ///
  /// The [screenshotDirectory] specifies where screenshots should be saved.
  /// If [autoScreenshots] is true, screenshots will be automatically captured on failures.
  const ScreenshotManager({
    required this.screenshotDirectory,
    this.autoScreenshots = false,
  });

  /// Captures a screenshot from the given WebDriver instance and saves it to a file.
  ///
  /// Returns the path to the saved screenshot file, or null if the capture failed.
  ///
  /// The [driver] is the WebDriver instance to capture from.
  /// The [name] is an optional name for the screenshot file. If not provided,
  /// a timestamp-based name will be generated.
  /// The [context] provides additional context for the filename (e.g., 'failure', 'debug').
  Future<String?> captureScreenshot(
    dynamic driver, {
    String? name,
    String? context,
  }) async {
    try {
      // Ensure the screenshot directory exists
      final dir = Directory(screenshotDirectory);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // Generate a unique filename
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final contextSuffix = context != null ? '_$context' : '';
      final filename = name != null
          ? '${name}_$timestamp$contextSuffix.png'
          : 'screenshot_$timestamp$contextSuffix.png';

      final filePath = '$screenshotDirectory/$filename';

      // Capture the screenshot
      List<int>? bytes;
      try {
        final dynamic list = await driver.captureScreenshotAsList();
        if (list is List) {
          bytes = List<int>.from(list);
        }
      } catch (_) {
        try {
          final b64 = await driver.captureScreenshotAsBase64();
          if (b64 is String) {
            bytes = base64.decode(b64);
          }
        } catch (_) {
          try {
            final any = await driver.captureScreenshot();
            if (any is List<int>) bytes = any;
          } catch (_) {}
        }
      }
      if (bytes == null) throw Exception('Screenshot capture failed');
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      return filePath;
    } catch (e) {
      // Don't let screenshot failures break the tests
      print('Warning: Failed to capture screenshot: $e');
      return null;
    }
  }

  /// Captures a screenshot synchronously from the given WebDriver instance.
  ///
  /// This is the synchronous version of [captureScreenshot] for use with
  /// synchronous browser implementations.
  ///
  /// Returns the path to the saved screenshot file, or null if the capture failed.
  String? captureScreenshotSync(
    dynamic driver, {
    String? name,
    String? context,
  }) {
    try {
      // Ensure the screenshot directory exists
      final dir = Directory(screenshotDirectory);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // Generate a unique filename
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '.');
      final contextSuffix = context != null ? '_$context' : '';
      final filename = name != null
          ? '${name}_$timestamp$contextSuffix.png'
          : 'screenshot_$timestamp$contextSuffix.png';

      final filePath = '$screenshotDirectory/$filename';

      // Capture the screenshot
      List<int>? bytes;
      try {
        final dynamic list = driver.captureScreenshotAsList();
        if (list is List) {
          bytes = List<int>.from(list);
        }
      } catch (_) {
        try {
          final b64 = driver.captureScreenshotAsBase64();
          if (b64 is String) {
            bytes = base64.decode(b64);
          }
        } catch (_) {
          try {
            final any = driver.captureScreenshot();
            if (any is List<int>) bytes = any;
          } catch (_) {}
        }
      }
      if (bytes == null) throw Exception('Screenshot capture failed');
      final file = File(filePath);
      file.writeAsBytesSync(bytes);

      return filePath;
    } catch (e) {
      // Don't let screenshot failures break the tests
      print('Warning: Failed to capture screenshot: $e');
      return null;
    }
  }

  /// Captures a failure screenshot with a descriptive name based on the error context.
  ///
  /// This method is specifically designed for automatic screenshot capture when
  /// tests fail. It generates a meaningful filename based on the action and selector
  /// that caused the failure.
  ///
  /// Returns the path to the saved screenshot file, or null if the capture failed.
  Future<String?> captureFailureScreenshot(
    dynamic driver, {
    String? action,
    String? selector,
    String? testName,
  }) async {
    if (!autoScreenshots) return null;

    final parts = <String>[];
    if (testName != null) parts.add(testName.replaceAll(' ', '_'));
    if (action != null) parts.add(action);
    parts.add('failure');

    final name = parts.join('_');
    final context = selector != null
        ? 'selector_${selector.replaceAll(RegExp(r'[^\w-]'), '_')}'
        : null;

    return await captureScreenshot(driver, name: name, context: context);
  }

  /// Synchronous version of [captureFailureScreenshot].
  String? captureFailureScreenshotSync(
    dynamic driver, {
    String? action,
    String? selector,
    String? testName,
  }) {
    if (!autoScreenshots) return null;

    final parts = <String>[];
    if (testName != null) parts.add(testName.replaceAll(' ', '_'));
    if (action != null) parts.add(action);
    parts.add('failure');

    final name = parts.join('_');
    final context = selector != null
        ? 'selector_${selector.replaceAll(RegExp(r'[^\w-]'), '_')}'
        : null;

    return captureScreenshotSync(driver, name: name, context: context);
  }

  /// Cleans up old screenshot files to prevent disk space issues.
  ///
  /// Removes screenshot files older than the specified [maxAge].
  /// If [maxAge] is not provided, files older than 7 days are removed.
  void cleanupOldScreenshots({Duration maxAge = const Duration(days: 7)}) {
    try {
      final dir = Directory(screenshotDirectory);
      if (!dir.existsSync()) return;

      final cutoffTime = DateTime.now().subtract(maxAge);

      for (final file in dir.listSync()) {
        if (file is File && file.path.endsWith('.png')) {
          final stat = file.statSync();
          if (stat.modified.isBefore(cutoffTime)) {
            file.deleteSync();
          }
        }
      }
    } catch (e) {
      print('Warning: Failed to cleanup old screenshots: $e');
    }
  }
}
