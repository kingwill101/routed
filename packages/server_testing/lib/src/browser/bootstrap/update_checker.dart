import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:io' show File, Directory;

import 'package:path/path.dart' as path;

import 'browser_registry.dart';
import 'version.dart' show Version;
import 'version.dart';

/// Periodically checks for available updates to installed browsers by comparing
/// locally recorded versions against a remote registry.
///
/// Maintains the state of installed browsers and the last check time in a
/// specified storage directory.
class BrowserUpdateChecker {
  /// The minimum duration that must pass between consecutive update checks.
  final Duration checkInterval;
  /// An optional callback function invoked when an update is found for an
  /// installed browser. Receives a [BrowserUpdate] object with details.
  final void Function(BrowserUpdate)? onUpdateAvailable;
  /// The directory used to store the last check timestamp and installed browser data.
  final Directory _storageDir;
  /// The filename for storing the timestamp of the last update check.
  static const String _lastCheckFile = 'last_check.json';
  /// The filename for storing the map of installed browser names to their versions.
  static const String _installedBrowsersFile = 'installed_browsers.json';

  /// Creates a [BrowserUpdateChecker] instance.
  ///
  /// Requires specifying the [checkInterval]. Optionally provide an
  /// [onUpdateAvailable] callback and a custom [storageDir]. Ensures the
  /// storage directory exists.
  BrowserUpdateChecker({
    this.checkInterval = const Duration(days: 1),
    this.onUpdateAvailable,
    String storageDir = '.routed/updates',
  }) : _storageDir = Directory(storageDir) {
    if (!_storageDir.existsSync()) {
      _storageDir.createSync(recursive: true);
    }
  }

  /// Reads the timestamp of the last successful update check from storage.
  ///
  /// Returns `null` if the file doesn't exist or cannot be parsed.
  Future<DateTime?> _getLastCheckTime() async {
    final file = File(path.join(_storageDir.path, _lastCheckFile));
    if (!file.existsSync()) return null;

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    return DateTime.parse(data['lastCheck'] as String);
  }

  /// Saves the given [time] as the last update check timestamp to storage.
  Future<void> _saveLastCheckTime(DateTime time) async {
    final file = File(path.join(_storageDir.path, _lastCheckFile));
    await file.writeAsString(jsonEncode({
      'lastCheck': time.toIso8601String(),
    }));
  }

  /// Reads the map of installed browser names and their recorded [Version]s
  /// from storage.
  ///
  /// Returns an empty map if the file doesn't exist or cannot be parsed.
  Future<Map<String, Version>> _getInstalledBrowsers() async {
    final file = File(path.join(_storageDir.path, _installedBrowsersFile));
    if (!file.existsSync()) return {};

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    return Map.fromEntries(data.entries
        .map((e) => MapEntry(e.key, Version.parse(e.value as String))));
  }

  /// Saves the provided map of installed [browsers] and their versions to storage.
  Future<void> _saveInstalledBrowsers(Map<String, Version> browsers) async {
    final file = File(path.join(_storageDir.path, _installedBrowsersFile));
    await file.writeAsString(jsonEncode(Map.fromEntries(
        browsers.entries.map((e) => MapEntry(e.key, e.value.toString())))));
  }

  /// Checks for available browser updates if the [checkInterval] has elapsed
  /// since the last check.
  ///
  /// Fetches the latest available browser versions using [BrowserRegistry],
  /// compares them against the locally recorded installed versions, and invokes
  /// the [onUpdateAvailable] callback for any browser with a newer version
  /// available. Updates the last check time after completion.
  Future<void> checkForUpdates() async {
    final lastCheck = await _getLastCheckTime();
    if (lastCheck != null &&
        DateTime.now().difference(lastCheck) < checkInterval) {
      return;
    }

    final registry = await BrowserRegistry.fetchAvailableBrowsers();
    final installed = await _getInstalledBrowsers();

    for (final browser in installed.entries) {
      final available = registry[browser.key];
      if (available == null) continue;

      final latest = available.first;
      if (latest.version > browser.value) {
        onUpdateAvailable?.call(BrowserUpdate(
          browser: browser.key,
          currentVersion: browser.value,
          latestVersion: latest.version,
        ));
      }
    }

    await _saveLastCheckTime(DateTime.now());
  }

  /// Records the installation of a specific [browser] at the given [version].
  ///
  /// Updates the stored map of installed browsers. This should be called after
  /// a successful browser installation or update.
  Future<void> recordInstall(String browser, Version version) async {
    final installed = await _getInstalledBrowsers();
    installed[browser] = version;
    await _saveInstalledBrowsers(installed);
  }
}

/// Represents information about an available update for an installed browser.
class BrowserUpdate {
  /// The name of the browser that has an update.
  final String browser;
  /// The currently installed version.
  final Version currentVersion;
  /// The latest available version found in the registry.
  final Version latestVersion;

  /// Creates a constant [BrowserUpdate] instance.
  const BrowserUpdate({
    required this.browser,
    required this.currentVersion,
    required this.latestVersion,
  });
}
