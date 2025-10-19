import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/platform_info.dart';

/// Provides canonical paths and URLs related to browser downloads and installations,
/// mirroring the structure expected by tools like Playwright.
class BrowserPaths {
  /// A list of base URLs for CDN mirrors hosting browser binary downloads.
  static const cdnMirrors = [
    'https://cdn.playwright.dev/dbazure/download/playwright',
    'https://playwright.download.prss.microsoft.com/dbazure/download/playwright',
    'https://cdn.playwright.dev',
  ];

  /// Defines the platform-specific relative path segments to the main browser
  /// executable within its installation directory.
  ///
  /// Keys are browser names ('chromium', 'firefox'), values are maps where keys
  /// are platform identifiers ('linux', 'mac', 'win') and values are lists of
  /// path segments.
  static const executablePaths = {
    'chromium': {
      'linux': ['chrome-linux', 'chrome'],
      'mac': ['chrome-mac', 'Chromium.app', 'Contents', 'MacOS', 'Chromium'],
      'win': ['chrome-win', 'chrome.exe'],
    },
    'firefox': {
      'linux': ['firefox', 'firefox'],
      'mac': ['firefox', 'Nightly.app', 'Contents', 'MacOS', 'firefox'],
      'win': ['firefox', 'firefox.exe'],
    },
  };

  /// Defines the platform-specific URL path templates used for downloading
  /// browser archives.
  ///
  /// Keys are browser names, values are maps where keys are specific platform IDs
  /// (e.g., 'ubuntu22.04-x64', 'mac13-arm64', 'win64') and values are URL path
  /// templates. The `%s` placeholder in the template is replaced with the
  /// browser revision number.
  static const downloadPaths = {
    'chromium': {
      'ubuntu20.04-x64': 'builds/chromium/%s/chromium-linux.zip',
      'ubuntu22.04-x64': 'builds/chromium/%s/chromium-linux.zip',
      'mac11': 'builds/chromium/%s/chromium-mac.zip',
      'mac11-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'mac12': 'builds/chromium/%s/chromium-mac.zip',
      'mac12-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'mac13': 'builds/chromium/%s/chromium-mac.zip',
      'mac13-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'win64': 'builds/chromium/%s/chromium-win64.zip',
    },
    'firefox': {
      'ubuntu20.04-x64': 'builds/firefox/%s/firefox-ubuntu-20.04.zip',
      'ubuntu22.04-x64': 'builds/firefox/%s/firefox-ubuntu-22.04.zip',
      'mac11': 'builds/firefox/%s/firefox-mac.zip',
      'mac11-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'mac12': 'builds/firefox/%s/firefox-mac.zip',
      'mac12-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'mac13': 'builds/firefox/%s/firefox-mac.zip',
      'mac13-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'win64': 'builds/firefox/%s/firefox-win64.zip',
    },
  };

  /// Gets the platform-specific relative path for the [browserName]'s executable
  /// within its installation folder.
  ///
  /// Returns `null` if the browser name or current platform is not defined in
  /// [executablePaths].
  static String? getExecutablePath(String browserName) {
    final paths = executablePaths[browserName];
    if (paths == null) return null;

    final platformKey = PlatformInfo.currentPlatform.toString().split('.').last;
    final segments = paths[platformKey];
    if (segments == null) return null;

    return path.joinAll(segments);
  }

  /// Gets a list of potential full download URLs for a specific [browserName]
  /// and [revision] by combining [cdnMirrors] and [downloadPaths] for the
  /// current platform.
  ///
  /// Returns an empty list if no download path template exists for the combination.
  static List<String> getDownloadUrls(String browserName, String revision) {
    final paths = downloadPaths[browserName];
    if (paths == null) return [];

    final platformId = PlatformInfo.platformId;
    final template = paths[platformId];
    if (template == null) return [];

    final downloadPath = template.replaceAll('%s', revision);

    return cdnMirrors.map((mirror) => '$mirror/$downloadPath').toList();
  }

  /// Gets the root directory used for storing browser installations and metadata.
  ///
  /// Root cache is ~/.server_testing by default (cross-platform), override with SERVER_TESTING_CACHE_DIR.
  static String getRegistryDirectory() {
    final override = Platform.environment['SERVER_TESTING_CACHE_DIR'];
    if (override != null && override.isNotEmpty) return override;

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return path.join(home, '.server_testing');
  }

  /// Gets the specific installation directory path for a given [browserName]
  /// and [revision] within the main registry directory obtained from
  /// [getRegistryDirectory].
  static String getBrowserInstallDirectory(String browserName,
      String revision,) {
    final registryDir = getRegistryDirectory();
    browserName = browserName.replaceAll('-', '_');
    return path.join(registryDir, '$browserName-$revision');
  }
}
