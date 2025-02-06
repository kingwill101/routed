import 'dart:io';
import 'package:path/path.dart' as path;

class InstallationValidator {
  static const String markerFileName = 'INSTALLATION_COMPLETE';
  static const Duration maxRevalidationPeriod = Duration(days: 30);

  static Future<bool> isValid(String browserDir) async {
    final markerFile = File(path.join(browserDir, markerFileName));
    if (!await markerFile.exists()) return false;

    final stat = await markerFile.stat();
    final age = DateTime.now().difference(stat.modified);
    return age < maxRevalidationPeriod;
  }

  static Future<void> markInstalled(String browserDir) async {
    final markerFile = File(path.join(browserDir, markerFileName));
    await markerFile.create(recursive: true);
    await markerFile.writeAsString(DateTime.now().toIso8601String());
  }

  static Future<void> validateDependencies(String browserDir) async {
    if (Platform.isLinux) {
      await _validateLinuxDependencies(browserDir);
    } else if (Platform.isWindows) {
      await _validateWindowsDependencies(browserDir);
    }
    // macOS doesn't need validation
  }

  static Future<void> _validateLinuxDependencies(String browserDir) async {
    final result = await Process.run('ldd', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('ldd is required for browser dependencies validation');
    }
    // Add more specific Linux dependency checks here
  }

  static Future<void> _validateWindowsDependencies(String browserDir) async {
    // Add Windows-specific dependency checks here
  }
}
