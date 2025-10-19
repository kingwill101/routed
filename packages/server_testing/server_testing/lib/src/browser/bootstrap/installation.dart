import 'dart:io';

import 'package:path/path.dart' as path;

/// Provides utilities for validating browser installations and checking
/// their dependencies. Manages a marker file to track successful installations
/// and avoid unnecessary revalidation.
class InstallationValidator {
  /// The filename used to mark a browser installation directory as complete
  /// and successfully validated (at least initially).
  static const String markerFileName = 'INSTALLATION_COMPLETE';

  /// The maximum age the marker file can have before an installation is
  /// considered potentially stale and requires revalidation (currently unused).
  static const Duration maxRevalidationPeriod = Duration(days: 30);

  /// Checks if the browser installation located in [browserDir] is considered valid.
  ///
  /// Currently, this primarily checks for the existence of the marker file
  /// ([markerFileName]) and potentially its age against [maxRevalidationPeriod].
  /// More comprehensive validation might be added later.
  static Future<bool> isValid(String browserDir) async {
    final markerFile = File(path.join(browserDir, markerFileName));
    if (!await markerFile.exists()) return false;

    final stat = await markerFile.stat();
    final age = DateTime.now().difference(stat.modified);
    return age < maxRevalidationPeriod;
  }

  /// Creates or updates the marker file within the specified [browserDir]
  /// to signify a successful installation or validation.
  ///
  /// Writes the current timestamp into the file.
  static Future<void> markInstalled(String browserDir) async {
    final markerFile = File(path.join(browserDir, markerFileName));
    await markerFile.create(recursive: true);
    await markerFile.writeAsString(DateTime.now().toIso8601String());
  }

  /// Performs platform-specific checks to validate that necessary system
  /// dependencies for the browser in [browserDir] are installed.
  ///
  /// Currently includes basic checks for Linux (`ldd`) and placeholders for Windows.
  /// This method is intended to be expanded with more specific checks based on
  /// browser requirements.
  static Future<void> validateDependencies(String browserDir) async {
    if (Platform.isLinux) {
      await _validateLinuxDependencies(browserDir);
    } else if (Platform.isWindows) {
      await _validateWindowsDependencies(browserDir);
    }
    // macOS doesn't need validation
  }

  /// Validates required dependencies for browsers on Linux.
  ///
  /// Currently checks for the presence of `ldd`. Should be expanded to check
  /// for specific libraries required by browsers like Chrome/Firefox.
  static Future<void> _validateLinuxDependencies(String browserDir) async {
    final result = await Process.run('ldd', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('ldd is required for browser dependencies validation');
    }
    // Add more specific Linux dependency checks here
  }

  /// Placeholder for validating required dependencies for browsers on Windows.
  ///
  /// This should be implemented with checks for necessary DLLs or runtime
  /// components if required.
  static Future<void> _validateWindowsDependencies(String browserDir) async {
    // Add Windows-specific dependency checks here
  }
}
