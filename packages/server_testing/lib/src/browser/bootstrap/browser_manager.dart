import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';

import '../browser_exception.dart';
import 'browser_json.dart';
import 'registry.dart';
import 'version.dart';

/// Manages the installation and retrieval of browser executables based on
/// configuration files (like `browsers.json`).
///
/// Note: This class appears to have some overlap with [Registry]. Consider
/// consolidating browser management logic.
class BrowserManager {
  // TODO: Consider using BrowserPaths.getRegistryDirectory() instead.
  /// The base directory path used for storing downloaded browser binaries.
  static const _baseDir = '.routed/browsers';
  /// Default browser versions used when a specific version is not requested.
  /// Consider sourcing this from [BrowserJson] or a registry.
  static final Map<String, Version> _browserVersions = {
    'chrome': Version.parse('114.0.5735.90'),
    'firefox': Version.parse('113.0.1'),
  };

  /// Gets the path to the installed executable for the specified [browserName].
  ///
  /// Uses the default version defined in [_browserVersions]. Returns `null`
  /// if the browser or the specific default version is not found installed
  /// in the [_baseDir]. Consider using [Registry.getExecutable] for a more
  /// robust approach integrated with `browsers.json`.
  static String? getBrowserPath(String browserName) {
    final version = _browserVersions[browserName];
    if (version == null) return null;

    final versionStr = version.toString();
    final installDir = path.join(_baseDir, browserName, versionStr);
    final executablePath = _getBrowserExecutablePath(browserName, installDir);

    return File(executablePath).existsSync() ? executablePath : null;
  }

  /// Determines the platform-specific executable filename within an [installDir]
  /// for a given [browser] name.
  static String _getBrowserExecutablePath(String browser, String installDir) {
    if (Platform.isWindows) {
      return path.join(installDir, '$browser.exe');
    } else if (Platform.isMacOS) {
      return browser == 'chrome'
          ? path.join(
              installDir, 'Chromium.app', 'Contents', 'MacOS', 'Chromium')
          : path.join(installDir, browser);
    }
    return path.join(installDir, browser);
  }

  /// Installs the specified list of [browsers] using the [Registry].
  ///
  /// This method correctly utilizes the [Registry] to handle installation based
  /// on the loaded `browsers.json` configuration.
  static Future<void> install(List<String> browsers) async {
    final registry = Registry(
      await BrowserJsonLoader.load(),
      requestedBrowser: browsers.first, // Pass the first browser as requested
    );

    final executables = browsers
        .map((b) => registry.getExecutable(b))
        .where((e) => e != null)
        .cast<Executable>()
        .toList();

    if (executables.isEmpty) {
      throw BrowserException('No valid browsers to install');
    }

    await registry.installExecutables(executables);
  }

  /// Installs a specific [browserName] and optionally a specific [version].
  ///
  /// Set [force] to true to reinstall even if the directory exists. Uses default
  /// versions from [_browserVersions] if [version] is null. Downloads from a
  /// hardcoded URL pattern in [_getDownloadUrl].
  ///
  /// Note: This method seems partially redundant with the more robust `install`
  /// method that uses the [Registry]. Prefer using `install`.
  static Future<void> installBrowser(
    String browserName, {
    Version? version,
    bool force = false,
  }) async {
    version ??= _browserVersions[browserName];
    final versionStr = version?.toString();
    if (version == null) {
      throw Exception('Unsupported browser: $browserName');
    }

    final installDir = path.join(_baseDir, browserName, versionStr ?? 'latest');
    if (!force && await Directory(installDir).exists()) {
      print('$browserName $version is already installed');
      return;
    }

    print('Installing $browserName ${versionStr ?? 'latest'}...');

    final url = _getDownloadUrl(browserName, versionStr ?? 'latest');
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to download browser');
    }

    await _extractBrowser(response.bodyBytes, installDir);
    await _setPermissions(installDir);
  }

  /// Constructs a hypothetical download URL based on platform, browser, and version.
  ///
  /// Note: This URL pattern is likely incorrect and does not reflect the actual
  /// CDN structure used by Playwright/browsers. Use [BrowserPaths.getDownloadUrls]
  /// instead.
  static String _getDownloadUrl(String browser, String version) {
    final platform = _getPlatform();
    return 'https://browser.repository/$platform/$browser-$version.zip';
  }

  /// Determines a simple platform identifier ('win64', 'mac', 'linux').
  ///
  /// Note: This is less specific than [PlatformInfo.platformId] which is
  /// needed for correct download URLs.
  static String _getPlatform() {
    if (Platform.isWindows) return 'win64';
    if (Platform.isMacOS) return 'mac';
    if (Platform.isLinux) return 'linux';
    throw Exception('Unsupported platform');
  }

  /// Extracts a downloaded browser archive (assumed to be ZIP format) represented
  /// by [bytes] into the [targetDir].
  static Future<void> _extractBrowser(List<int> bytes, String targetDir) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File(path.join(targetDir, filename))
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }
  }

  /// Sets executable permissions (+x) recursively on the contents of [dir].
  ///
  /// This is typically needed on Linux and macOS after extraction. Does nothing
  /// on Windows.
  static Future<void> _setPermissions(String dir) async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['-R', '+x', dir]);
    }
  }
}
