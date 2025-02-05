import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:io' show File, Directory;

import 'package:path/path.dart' as path;
import 'browser_registry.dart';
import 'version.dart';
import 'version.dart' show Version;

class BrowserUpdateChecker {
  final Duration checkInterval;
  final void Function(BrowserUpdate)? onUpdateAvailable;
  final Directory _storageDir;
  static const String _lastCheckFile = 'last_check.json';
  static const String _installedBrowsersFile = 'installed_browsers.json';

  BrowserUpdateChecker({
    this.checkInterval = const Duration(days: 1),
    this.onUpdateAvailable,
    String storageDir = '.routed/updates',
  }) : _storageDir = Directory(storageDir) {
    if (!_storageDir.existsSync()) {
      _storageDir.createSync(recursive: true);
    }
  }

  Future<DateTime?> _getLastCheckTime() async {
    final file = File(path.join(_storageDir.path, _lastCheckFile));
    if (!file.existsSync()) return null;

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    return DateTime.parse(data['lastCheck'] as String);
  }

  Future<void> _saveLastCheckTime(DateTime time) async {
    final file = File(path.join(_storageDir.path, _lastCheckFile));
    await file.writeAsString(jsonEncode({
      'lastCheck': time.toIso8601String(),
    }));
  }

  Future<Map<String, Version>> _getInstalledBrowsers() async {
    final file = File(path.join(_storageDir.path, _installedBrowsersFile));
    if (!file.existsSync()) return {};

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    return Map.fromEntries(
      data.entries.map((e) => MapEntry(e.key, Version.parse(e.value as String)))
    );
  }

  Future<void> _saveInstalledBrowsers(Map<String, Version> browsers) async {
    final file = File(path.join(_storageDir.path, _installedBrowsersFile));
    await file.writeAsString(jsonEncode(
      Map.fromEntries(
        browsers.entries.map((e) => MapEntry(e.key, e.value.toString()))
      )
    ));
  }

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

  Future<void> recordInstall(String browser, Version version) async {
    final installed = await _getInstalledBrowsers();
    installed[browser] = version;
    await _saveInstalledBrowsers(installed);
  }
}

class BrowserUpdate {
  final String browser;
  final Version currentVersion;
  final Version latestVersion;

  const BrowserUpdate({
    required this.browser,
    required this.currentVersion,
    required this.latestVersion,
  });
}
