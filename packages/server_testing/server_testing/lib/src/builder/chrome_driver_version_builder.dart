import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart'
    show AssetId, BuildStep, Builder, BuilderOptions, log;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../browser/bootstrap/platform_info.dart';

// Builder factory function
Builder chromeDriverVersionBuilder(BuilderOptions options) =>
    ChromeDriverVersionBuilder();

/// A build_runner Builder that fetches the latest known good ChromeDriver version
/// and generates a Dart file containing constants for the version and base download URL.
class ChromeDriverVersionBuilder implements Builder {
  // URL providing known good versions with download links for ChromeDriver
  static const String _versionsUrl =
      'https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json';

  /// Maps PlatformInfo data to the platform keys used in the ChromeDriver download JSON.
  String _mapToPlatformKey(BrowserPlatform platform, String architecture) {
    switch (platform) {
      case BrowserPlatform.linux:
        return 'linux64';
      case BrowserPlatform.mac:
        return architecture == 'arm64' ? 'mac-arm64' : 'mac-x64';
      case BrowserPlatform.win:
        // ChromeDriver typically uses win64 for 64-bit Windows
        return architecture == 'x64' ? 'win64' : 'win32';
    }
  }

  /// Gets the architecture string directly since we can't access the private method in PlatformInfo.
  String _getArchitecture() {
    // Use PlatformInfo.platformId which includes architecture information
    final platformId = PlatformInfo.platformId;
    if (platformId.contains('arm64')) {
      return 'arm64';
    }
    return 'x64'; // Default to x64 for other cases
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    // Define the output asset ID based on the input ID convention
    final outputId = AssetId(
      buildStep.inputId.package,
      // Place the generated file alongside the manager that uses it
      p.join(
        'lib',
        'src',
        'browser',
        'bootstrap',
        'driver',
        'chrome_driver_version.dart',
      ),
    );

    try {
      log.info(
        'Fetching known good ChromeDriver versions from $_versionsUrl...',
      );
      final response = await http.get(Uri.parse(_versionsUrl));

      if (response.statusCode != 200) {
        log.severe(
          // Use BuildException for build errors
          'Failed to fetch ChromeDriver versions: HTTP ${response.statusCode} ${response.reasonPhrase}',
        );
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final versions = data['versions'] as List<dynamic>?; // Make nullable

      if (versions == null || versions.isEmpty) {
        log.severe('No versions found in the fetched ChromeDriver data.');
        return;
      }

      // Determine desired Chrome major to match bundled Chromium in browsers.json
      String? desiredMajor;
      try {
        final pwResp = await http.get(
          Uri.parse(
            'https://raw.githubusercontent.com/microsoft/playwright/main/packages/playwright-core/browsers.json',
          ),
        );
        if (pwResp.statusCode == 200) {
          final pw = json.decode(pwResp.body) as Map<String, dynamic>;
          final browsers = (pw['browsers'] as List)
              .cast<Map<String, dynamic>>();
          final chromium = browsers.firstWhere(
            (b) => (b['name'] as String).startsWith('chromium'),
          );
          final version = chromium['browserVersion'] as String?;
          if (version != null && version.contains('.')) {
            desiredMajor = version.split('.').first;
          }
        }
      } catch (_) {}

      // Find the latest chromedriver matching desired major if available, else latest
      Map<String, dynamic>? latestVersionData;
      for (int i = versions.length - 1; i >= 0; i--) {
        final versionData = versions[i] as Map<String, dynamic>;
        final ver = versionData['version'] as String?;
        final hasDriver =
            versionData.containsKey('downloads') &&
            versionData['downloads'] is Map &&
            (versionData['downloads'] as Map).containsKey('chromedriver') &&
            versionData['downloads']['chromedriver'] is List &&
            (versionData['downloads']['chromedriver'] as List).isNotEmpty;
        if (!hasDriver) continue;
        if (desiredMajor != null &&
            ver != null &&
            ver.startsWith('$desiredMajor.')) {
          latestVersionData = versionData;
          break; // Found latest matching major
        }
        // If no desiredMajor or none matched, keep the last valid encountered as fallback
        latestVersionData ??= versionData;
      }

      if (latestVersionData == null) {
        log.severe('No versions found with valid ChromeDriver downloads.');
        return;
      }

      final latestVersion = latestVersionData['version'] as String?;
      final chromedriverDownloads =
          latestVersionData['downloads']['chromedriver'] as List<dynamic>?;

      if (latestVersion == null ||
          chromedriverDownloads == null ||
          chromedriverDownloads.isEmpty) {
        log.severe(
          'Latest valid entry is missing version or chromedriver download links.',
        );
        return;
      }

      log.info('Latest known good ChromeDriver version found: $latestVersion');

      // Collect all platform download URLs
      final platformUrls = <String, String>{};
      final platformFilenames = <String, String>{};

      for (final download in chromedriverDownloads) {
        final downloadMap = download as Map<String, dynamic>;
        final platform = downloadMap['platform'] as String;
        final url = downloadMap['url'] as String;

        platformUrls[platform] = url;

        // Extract the filename from the URL
        final uri = Uri.parse(url);
        final filename = uri.pathSegments.last;
        platformFilenames[platform] = filename;
      }

      log.info(
        'Found download URLs for platforms: ${platformUrls.keys.join(', ')}',
      );

      // Extract base download URL (common prefix)
      // The URL format is like: https://storage.googleapis.com/chrome-for-testing-public/115.0.5763.0/win64/chromedriver-win64.zip
      final sampleUrl = platformUrls.values.first;
      final versionPart = '/$latestVersion/';
      final versionIndex = sampleUrl.indexOf(versionPart);
      if (versionIndex == -1) {
        log.severe(
          "Could not determine base URL structure from URL: $sampleUrl",
        );
        return;
      }

      // Include the trailing slash of the base part
      final baseUrl = sampleUrl.substring(0, versionIndex);

      log.info('Determined ChromeDriver base download URL: $baseUrl');

      // Get the current platform for convenience
      final currentPlatform = PlatformInfo.currentPlatform;
      final architecture = _getArchitecture();
      final platformKey = _mapToPlatformKey(currentPlatform, architecture);

      // Format the platform URLs map as a Dart map literal
      final platformUrlsMapString = platformUrls.entries
          .map((entry) => "  '${entry.key}': '${entry.value}'")
          .join(',\n');

      // Format the platform filenames map as a Dart map literal
      final platformFilenamesMapString = platformFilenames.entries
          .map((entry) => "  '${entry.key}': '${entry.value}'")
          .join(',\n');

      // Generate the Dart code content
      final outputContent =
          """
/// Generated constants related to the ChromeDriver version and download URL.
///
/// This file is generated by a build process and should not be edited manually.
/// It provides the specific version and base download URL used by [ChromeDriverManager].
library;
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated at: ${DateTime.now().toUtc().toIso8601String()}

/// The latest known good version of ChromeDriver based on fetch time.
const String chromeDriverVersion = '$latestVersion';

/// The base URL prefix for downloading ChromeDriver assets.
/// Specific version, platform, and filename should be appended.
/// Example structure: [chromeDriverBaseUrl]/[chromeDriverVersion]/[platform]/[filename]
const String chromeDriverBaseUrl = '$baseUrl';

/// Map of platform identifiers to their complete download URLs.
/// Use this to look up the appropriate download URL for a specific platform.
const Map<String, String> chromeDriverUrls = {
$platformUrlsMapString
};

/// Map of platform identifiers to their download filenames.
/// Use this to determine the correct extraction path for a specific platform.
const Map<String, String> chromeDriverFilenames = {
$platformFilenamesMapString
};

/// The detected platform at build time (for reference only).
/// At runtime, use platform detection logic to select the appropriate URL.
const String buildTimePlatform = '$platformKey';
""";

      // Write the generated file
      await buildStep.writeAsString(outputId, outputContent);
      log.info('Successfully generated $outputId');
    } catch (e, s) {
      log.severe(
        'Failed to generate ChromeDriver version file ($outputId)',
        e,
        s,
      );
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
    r'lib/src/browser/bootstrap/driver/chrome_driver_manager_base.dart': [
      'lib/src/browser/bootstrap/driver/chrome_driver_version.dart',
    ],
  };
}
