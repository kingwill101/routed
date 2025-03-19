import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart'
    show AssetId, BuildStep, Builder, BuilderOptions, log;
import 'package:http/http.dart' as http;

Builder createGeckoDriverVersionBuilder(BuilderOptions options) =>
    GeckoDriverVersionBuilder();

class GeckoDriverVersionBuilder implements Builder {
  static const String githubApiUrl =
      'https://api.github.com/repos/mozilla/geckodriver/releases/latest';

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    log.info('Starting GeckoDriver version builder...');

    final outputId = AssetId(
      buildStep.inputId.package,
      'lib/src/browser/bootstrap/driver/gecko_driver_version.dart',
    );

    log.info('Fetching latest GeckoDriver version from GitHub API');

    try {
      final client = http.Client();
      final response = await client.get(
        Uri.parse(githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      client.close();

      if (response.statusCode != 200) {
        log.severe(
            'Failed to fetch latest GeckoDriver version: ${response.statusCode} ${response.body}');
        return;
      }

      log.info('Successfully fetched GeckoDriver release info');

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = json['tag_name'] as String;

      log.info('Latest GeckoDriver version: $latestVersion');

      final dartContent = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated at: ${DateTime.now().toIso8601String()}

/// The latest version of GeckoDriver
const geckoDriverVersion = '$latestVersion';

/// The base URL for GeckoDriver downloads
const geckoDriverBaseUrl = 'https://github.com/mozilla/geckodriver/releases/download';
''';

      log.info('Writing to ${outputId.path}');
      await buildStep.writeAsString(outputId, dartContent);
      log.info('Successfully wrote gecko_driver_version.dart');
    } catch (e, stack) {
      log.severe('Error in GeckoDriver version builder: $e\n$stack');
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/src/browser/bootstrap/driver/gecko_driver_manager_base.dart': [
          'lib/src/browser/bootstrap/driver/gecko_driver_version.dart'
        ]
      };
}
