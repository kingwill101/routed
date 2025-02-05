import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:routed_testing/src/browser/bootstrap/platform_info.dart';

class BrowserPaths {
  static const cdnMirrors = [
    'https://cdn.playwright.dev/dbazure/download/playwright',
    'https://playwright.download.prss.microsoft.com/dbazure/download/playwright',
    'https://cdn.playwright.dev',
  ];

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

  static String? getExecutablePath(String browserName) {
    final paths = executablePaths[browserName];
    if (paths == null) return null;

    final platformKey = PlatformInfo.currentPlatform.toString().split('.').last;
    final segments = paths[platformKey];
    if (segments == null) return null;

    return path.joinAll(segments);
  }

  static List<String> getDownloadUrls(String browserName, String revision) {
    final paths = downloadPaths[browserName];
    if (paths == null) return [];

    final platformId = PlatformInfo.platformId;
    final template = paths[platformId];
    if (template == null) return [];

    final downloadPath = template.replaceAll('%s', revision);

    return cdnMirrors.map((mirror) => '$mirror/$downloadPath').toList();
  }

  // Add to existing BrowserPaths class
  static String getRegistryDirectory() {
    final envDefined = Platform.environment['PLAYWRIGHT_BROWSERS_PATH'];
    if (envDefined == '0') {
      return path.join(Directory.current.path, '.local-browsers');
    }
    if (envDefined != null) {
      return envDefined;
    }

    String cacheDirectory;
    if (Platform.isLinux) {
      cacheDirectory = Platform.environment['XDG_CACHE_HOME'] ??
          path.join(Platform.environment['HOME'] ?? '', '.cache');
    } else if (Platform.isMacOS) {
      cacheDirectory =
          path.join(Platform.environment['HOME'] ?? '', 'Library', 'Caches');
    } else if (Platform.isWindows) {
      cacheDirectory = Platform.environment['LOCALAPPDATA'] ??
          path.join(
              Platform.environment['USERPROFILE'] ?? '', 'AppData', 'Local');
    } else {
      throw Exception('Unsupported platform: ${Platform.operatingSystem}');
    }

    return path.join(cacheDirectory, 'ms-playwright');
  }

  static String getBrowserInstallDirectory(
      String browserName, String revision) {
    final registryDir = getRegistryDirectory();
    browserName = browserName.replaceAll('-', '_');
    return path.join(registryDir, '$browserName-$revision');
  }
}
