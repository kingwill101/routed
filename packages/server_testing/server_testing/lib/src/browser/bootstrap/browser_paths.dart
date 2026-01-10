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

  /// Base URL for Chrome for Testing downloads.
  static const _chromeForTestingBaseUrl =
      'https://storage.googleapis.com/chrome-for-testing-public';

  /// Defines platform-specific candidate paths to the main browser executable
  /// within its installation directory.
  ///
  /// Keys are browser names ('chromium', 'firefox', 'webkit',
  /// 'chromium-headless-shell'). Values are maps where keys are platform
  /// identifiers ('linux', 'mac', 'win') and values are ordered lists of
  /// path-segment lists. The first existing candidate is chosen at runtime; the
  /// first entry is used as the default when nothing exists yet.
  static const executablePathCandidates = {
    'chromium': {
      'linux': [
        ['chrome-linux64', 'chrome'],
        ['chrome-linux', 'chrome'],
      ],
      'mac': [
        [
          'chrome-mac-arm64',
          'Google Chrome for Testing.app',
          'Contents',
          'MacOS',
          'Google Chrome for Testing',
        ],
        [
          'chrome-mac-x64',
          'Google Chrome for Testing.app',
          'Contents',
          'MacOS',
          'Google Chrome for Testing',
        ],
        ['chrome-mac', 'Chromium.app', 'Contents', 'MacOS', 'Chromium'],
      ],
      'win': [
        ['chrome-win64', 'chrome.exe'],
        ['chrome-win', 'chrome.exe'],
      ],
    },
    'chromium-headless-shell': {
      'linux': [
        ['chrome-headless-shell-linux64', 'chrome-headless-shell'],
        ['chrome-linux', 'headless_shell'],
      ],
      'mac': [
        ['chrome-headless-shell-mac-x64', 'chrome-headless-shell'],
        ['chrome-headless-shell-mac-arm64', 'chrome-headless-shell'],
      ],
      'win': [
        ['chrome-headless-shell-win64', 'chrome-headless-shell.exe'],
      ],
    },
    'firefox': {
      'linux': [
        ['firefox', 'firefox'],
      ],
      'mac': [
        ['firefox', 'Nightly.app', 'Contents', 'MacOS', 'firefox'],
      ],
      'win': [
        ['firefox', 'firefox.exe'],
      ],
    },
    'webkit': {
      'linux': [
        ['pw_run.sh'],
      ],
      'mac': [
        ['pw_run.sh'],
      ],
      'win': [
        ['Playwright.exe'],
      ],
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
      'ubuntu24.04-x64': 'builds/chromium/%s/chromium-linux.zip',
      'mac11': 'builds/chromium/%s/chromium-mac.zip',
      'mac11-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'mac12': 'builds/chromium/%s/chromium-mac.zip',
      'mac12-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'mac13': 'builds/chromium/%s/chromium-mac.zip',
      'mac13-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'mac14': 'builds/chromium/%s/chromium-mac.zip',
      'mac14-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'mac15': 'builds/chromium/%s/chromium-mac.zip',
      'mac15-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
      'win64': 'builds/chromium/%s/chromium-win64.zip',
    },
    'chromium-headless-shell': {
      'ubuntu20.04-x64':
          '$_chromeForTestingBaseUrl/%s/linux64/chrome-headless-shell-linux64.zip',
      'ubuntu22.04-x64':
          '$_chromeForTestingBaseUrl/%s/linux64/chrome-headless-shell-linux64.zip',
      'ubuntu24.04-x64':
          '$_chromeForTestingBaseUrl/%s/linux64/chrome-headless-shell-linux64.zip',
      'ubuntu20.04-arm64':
          'builds/chromium/%s/chromium-headless-shell-linux-arm64.zip',
      'ubuntu22.04-arm64':
          'builds/chromium/%s/chromium-headless-shell-linux-arm64.zip',
      'ubuntu24.04-arm64':
          'builds/chromium/%s/chromium-headless-shell-linux-arm64.zip',
      'debian11-x64':
          '$_chromeForTestingBaseUrl/%s/linux64/chrome-headless-shell-linux64.zip',
      'debian11-arm64':
          'builds/chromium/%s/chromium-headless-shell-linux-arm64.zip',
      'debian12-x64':
          '$_chromeForTestingBaseUrl/%s/linux64/chrome-headless-shell-linux64.zip',
      'debian12-arm64':
          'builds/chromium/%s/chromium-headless-shell-linux-arm64.zip',
      'debian13-x64':
          '$_chromeForTestingBaseUrl/%s/linux64/chrome-headless-shell-linux64.zip',
      'debian13-arm64':
          'builds/chromium/%s/chromium-headless-shell-linux-arm64.zip',
      'mac11':
          '$_chromeForTestingBaseUrl/%s/mac-x64/chrome-headless-shell-mac-x64.zip',
      'mac11-arm64':
          '$_chromeForTestingBaseUrl/%s/mac-arm64/chrome-headless-shell-mac-arm64.zip',
      'mac12':
          '$_chromeForTestingBaseUrl/%s/mac-x64/chrome-headless-shell-mac-x64.zip',
      'mac12-arm64':
          '$_chromeForTestingBaseUrl/%s/mac-arm64/chrome-headless-shell-mac-arm64.zip',
      'mac13':
          '$_chromeForTestingBaseUrl/%s/mac-x64/chrome-headless-shell-mac-x64.zip',
      'mac13-arm64':
          '$_chromeForTestingBaseUrl/%s/mac-arm64/chrome-headless-shell-mac-arm64.zip',
      'mac14':
          '$_chromeForTestingBaseUrl/%s/mac-x64/chrome-headless-shell-mac-x64.zip',
      'mac14-arm64':
          '$_chromeForTestingBaseUrl/%s/mac-arm64/chrome-headless-shell-mac-arm64.zip',
      'mac15':
          '$_chromeForTestingBaseUrl/%s/mac-x64/chrome-headless-shell-mac-x64.zip',
      'mac15-arm64':
          '$_chromeForTestingBaseUrl/%s/mac-arm64/chrome-headless-shell-mac-arm64.zip',
      'win64':
          '$_chromeForTestingBaseUrl/%s/win64/chrome-headless-shell-win64.zip',
    },
    'firefox': {
      'ubuntu20.04-x64': 'builds/firefox/%s/firefox-ubuntu-20.04.zip',
      'ubuntu22.04-x64': 'builds/firefox/%s/firefox-ubuntu-22.04.zip',
      'ubuntu24.04-x64': 'builds/firefox/%s/firefox-ubuntu-24.04.zip',
      'mac11': 'builds/firefox/%s/firefox-mac.zip',
      'mac11-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'mac12': 'builds/firefox/%s/firefox-mac.zip',
      'mac12-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'mac13': 'builds/firefox/%s/firefox-mac.zip',
      'mac13-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'mac14': 'builds/firefox/%s/firefox-mac.zip',
      'mac14-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'mac15': 'builds/firefox/%s/firefox-mac.zip',
      'mac15-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
      'win64': 'builds/firefox/%s/firefox-win64.zip',
    },
    'webkit': {
      'ubuntu20.04-x64': 'builds/webkit/%s/webkit-ubuntu-20.04.zip',
      'ubuntu22.04-x64': 'builds/webkit/%s/webkit-ubuntu-22.04.zip',
      'ubuntu24.04-x64': 'builds/webkit/%s/webkit-ubuntu-24.04.zip',
      'ubuntu20.04-arm64': 'builds/webkit/%s/webkit-ubuntu-20.04-arm64.zip',
      'ubuntu22.04-arm64': 'builds/webkit/%s/webkit-ubuntu-22.04-arm64.zip',
      'ubuntu24.04-arm64': 'builds/webkit/%s/webkit-ubuntu-24.04-arm64.zip',
      'debian11-x64': 'builds/webkit/%s/webkit-debian-11.zip',
      'debian11-arm64': 'builds/webkit/%s/webkit-debian-11-arm64.zip',
      'debian12-x64': 'builds/webkit/%s/webkit-debian-12.zip',
      'debian12-arm64': 'builds/webkit/%s/webkit-debian-12-arm64.zip',
      'debian13-x64': 'builds/webkit/%s/webkit-debian-13.zip',
      'debian13-arm64': 'builds/webkit/%s/webkit-debian-13-arm64.zip',
      'mac11': 'builds/webkit/%s/webkit-mac-11.zip',
      'mac11-arm64': 'builds/webkit/%s/webkit-mac-11-arm64.zip',
      'mac12': 'builds/webkit/%s/webkit-mac-12.zip',
      'mac12-arm64': 'builds/webkit/%s/webkit-mac-12-arm64.zip',
      'mac13': 'builds/webkit/%s/webkit-mac-13.zip',
      'mac13-arm64': 'builds/webkit/%s/webkit-mac-13-arm64.zip',
      'mac14': 'builds/webkit/%s/webkit-mac-14.zip',
      'mac14-arm64': 'builds/webkit/%s/webkit-mac-14-arm64.zip',
      'mac15': 'builds/webkit/%s/webkit-mac-15.zip',
      'mac15-arm64': 'builds/webkit/%s/webkit-mac-15-arm64.zip',
      'win64': 'builds/webkit/%s/webkit-win64.zip',
    },
  };

  /// Gets the platform-specific relative path for the [browserName]'s executable
  /// within its installation folder.
  ///
  /// Returns `null` if the browser name or current platform is not defined in
  /// [executablePaths].
  static List<String> getExecutablePathCandidates(String browserName) {
    final paths = executablePathCandidates[browserName];
    if (paths == null) return const [];

    final platformKey = PlatformInfo.currentPlatform.toString().split('.').last;
    final candidates = paths[platformKey];
    if (candidates == null) return const [];

    return candidates.map(path.joinAll).toList(growable: false);
  }

  /// Gets the default platform-specific relative path for the [browserName]'s
  /// executable within its installation folder.
  ///
  /// Returns `null` if the browser name or current platform is not defined in
  /// [executablePathCandidates].
  static String? getExecutablePath(String browserName) {
    final candidates = getExecutablePathCandidates(browserName);
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  /// Resolves the most likely executable path for an installed browser by
  /// checking candidate paths under [installDir].
  ///
  /// Returns the first existing candidate. If nothing exists yet, returns the
  /// default candidate (or `null` if unsupported).
  static String? resolveExecutablePath(String browserName, String installDir) {
    final candidates = getExecutablePathCandidates(browserName);
    for (final candidate in candidates) {
      final fullPath = path.join(installDir, candidate);
      if (File(fullPath).existsSync()) {
        return candidate;
      }
    }
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  /// Gets a list of potential full download URLs for a specific [browserName]
  /// and [revision] by combining [cdnMirrors] and [downloadPaths] for the
  /// current platform.
  ///
  /// Returns an empty list if no download path template exists for the combination.
  static List<String> getDownloadUrls(
    String browserName,
    String revision, {
    String? browserVersion,
    String? platformOverride,
  }) {
    final paths = downloadPaths[browserName];
    if (paths == null) return [];

    final platformId = platformOverride ?? PlatformInfo.platformId;

    for (final candidate in _candidatePlatformIds(platformId)) {
      final template = paths[candidate] ?? _stripArchFallback(paths, candidate);
      if (template == null) continue;

      final token = _selectDownloadVersion(template, revision, browserVersion);
      final downloadPath = template.replaceAll('%s', token);
      if (downloadPath.startsWith('http://') ||
          downloadPath.startsWith('https://')) {
        return [downloadPath];
      }
      return cdnMirrors.map((mirror) => '$mirror/$downloadPath').toList();
    }

    return [];
  }

  static String _selectDownloadVersion(
    String template,
    String revision,
    String? browserVersion,
  ) {
    if (browserVersion != null &&
        browserVersion.isNotEmpty &&
        template.contains(_chromeForTestingBaseUrl)) {
      return browserVersion;
    }
    return revision;
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
  static String getBrowserInstallDirectory(
    String browserName,
    String revision,
  ) {
    final registryDir = getRegistryDirectory();
    browserName = browserName.replaceAll('-', '_');
    return path.join(registryDir, '$browserName-$revision');
  }

  /// Generates a prioritized list of platform identifiers to try when looking
  /// up download URLs. Falls back to older but compatible platforms where
  /// possible (e.g., ubuntu24.04 → ubuntu22.04 → ubuntu20.04).
  static List<String> _candidatePlatformIds(String platformId) {
    final seen = <String>{};
    final result = <String>[];

    String normalize(String id) => id.trim();

    void add(String id) {
      id = normalize(id);
      if (id.isEmpty || !seen.add(id)) return;
      result.add(id);
    }

    add(platformId);

    final parts = platformId.split('-');
    if (parts.isEmpty) return result;

    final base = parts.first;
    final arch = parts.length > 1 ? parts.sublist(1).join('-') : '';

    Iterable<String> linuxFallbacks() sync* {
      final match = RegExp(r'ubuntu(\d+)\.(\d+)').firstMatch(base);
      if (match != null) {
        final major = int.tryParse(match.group(1) ?? '');
        final minor = match.group(2) ?? '04';
        if (major != null) {
          for (
            var fallbackMajor = major - 2;
            fallbackMajor >= 20;
            fallbackMajor -= 2
          ) {
            final paddedMajor = fallbackMajor.toString().padLeft(2, '0');
            yield 'ubuntu$paddedMajor.$minor';
          }
          return;
        }
      }

      final debianMatch = RegExp(r'debian(\d+)').firstMatch(base);
      if (debianMatch != null) {
        final major = int.tryParse(debianMatch.group(1) ?? '');
        if (major != null) {
          for (
            var fallbackMajor = major - 1;
            fallbackMajor >= 11;
            fallbackMajor--
          ) {
            yield 'debian$fallbackMajor';
          }
        }
      }

      if (base == 'linux') {
        yield 'ubuntu22.04';
        yield 'ubuntu20.04';
        yield 'debian12';
        yield 'debian11';
      }
    }

    Iterable<String> macFallbacks() sync* {
      final match = RegExp(r'mac(\d+)').firstMatch(base);
      if (match != null) {
        final major = int.tryParse(match.group(1) ?? '');
        if (major != null) {
          for (
            var fallbackMajor = major - 1;
            fallbackMajor >= 11;
            fallbackMajor--
          ) {
            yield 'mac$fallbackMajor';
          }
        }
      }
    }

    if (base.startsWith('ubuntu') ||
        base.startsWith('debian') ||
        base.startsWith('linux')) {
      for (final fallbackBase in linuxFallbacks()) {
        final fallback = arch.isEmpty ? fallbackBase : '$fallbackBase-$arch';
        add(fallback);
      }
    } else if (base.startsWith('mac')) {
      for (final fallbackBase in macFallbacks()) {
        final fallback = arch.isEmpty ? fallbackBase : '$fallbackBase-$arch';
        add(fallback);
      }
    }

    return result;
  }

  /// Attempts to fall back to an entry that omits the architecture suffix
  /// (e.g., mac13-x64 → mac13) for maps that encode x64 builds without an arch.
  static String? _stripArchFallback(
    Map<String, String> paths,
    String candidate,
  ) {
    final parts = candidate.split('-');
    if (parts.length <= 1) return null;

    final base = parts.first;
    return paths[base];
  }
}
