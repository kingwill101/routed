import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart'
    show AssetId, BuildStep, Builder, BuilderOptions, log;
import 'package:http/http.dart' as http;

Builder createBrowserJsonBuilder(BuilderOptions options) =>
    BrowserJsonBuilder();

class BrowserJsonBuilder implements Builder {
  static const String browsersJsonUrl =
      'https://raw.githubusercontent.com/microsoft/playwright/main/packages/playwright-core/browsers.json';

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    log.info('Starting browser json builder...');

    final outputId = AssetId(
      buildStep.inputId.package,
      'lib/src/browser/bootstrap/browsers_json_const.dart',
    );

    log.info('Fetching browsers.json from $browsersJsonUrl');

    try {
      final client = http.Client();
      final response = await client.get(Uri.parse(browsersJsonUrl));
      client.close();

      if (response.statusCode != 200) {
        log.severe(
            'Failed to fetch browsers.json: ${response.statusCode} ${response.body}');
        return;
      }

      log.info('Successfully fetched browsers.json');

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final browsers = (json['browsers'] as List).map((b) => '''
        BrowserEntry(
          name: '${b['name']}',
          revision: '${b['revision']}',
          browserVersion: ${b['browserVersion'] != null ? "'${b['browserVersion']}'" : 'null'},
          installByDefault: ${b['installByDefault']},
          revisionOverrides: ${b['revisionOverrides'] != null ? _mapToString(b['revisionOverrides'] as Map<String, dynamic>) : 'null'},
        )''').join(',\n    ');

      final dartContent = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated at: ${DateTime.now().toIso8601String()}

import 'browser_json.dart';

final browserJsonData = BrowserJson(
  comment: '${json['comment']}',
  browsers: [
    $browsers
  ],
);
''';

      log.info('Writing to ${outputId.path}');
      await buildStep.writeAsString(outputId, dartContent);
      log.info('Successfully wrote browsers_json_const.dart');
    } catch (e, stack) {
      log.severe('Error in browser json builder: $e\n$stack');
    }
  }

  String _mapToString(Map<String, dynamic> map) {
    final entries =
        map.entries.map((e) => "'${e.key}': '${e.value}'").join(', ');
    return '{$entries}';
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/src/browser/bootstrap/browser_json.dart': [
          'lib/src/browser/bootstrap/browsers_json_const.dart'
        ]
      };
}
