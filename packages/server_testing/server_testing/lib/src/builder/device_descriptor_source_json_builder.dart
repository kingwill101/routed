import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart'
    show AssetId, BuildStep, Builder, BuilderOptions, log;
import 'package:http/http.dart' as http;

Builder createDeviceDescriptorSourceJsonBuilder(BuilderOptions options) =>
    BrowserJsonBuilder();

class BrowserJsonBuilder implements Builder {
  static const String devicesJsonUrl =
      'https://raw.githubusercontent.com/microsoft/playwright/main/packages/playwright-core/src/server/deviceDescriptorsSource.json';

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    log.info('Starting device json builder...');

    final outputId = AssetId(
      buildStep.inputId.package,
      'lib/src/browser/bootstrap/devices_json_const.dart',
    );

    log.info('Fetching devices.json from $devicesJsonUrl');

    try {
      final client = http.Client();
      final response = await client.get(Uri.parse(devicesJsonUrl));
      client.close();

      if (response.statusCode != 200) {
        log.severe(
          'Failed to fetch devices.json: ${response.statusCode} ${response.body}',
        );
        return;
      }

      log.info('Successfully fetched devices.json');

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final devices = json.entries
          .map((entry) {
            final device = entry.value as Map<String, dynamic>;
            return '''
        '${entry.key}': Device(
          userAgent: '${device['userAgent']}',
          viewport: Viewport(
            width: ${device['viewport']['width']},
            height: ${device['viewport']['height']}
          ),
          deviceScaleFactor: ${device['deviceScaleFactor']},
          isMobile: ${device['isMobile']},
          hasTouch: ${device['hasTouch']},
          defaultBrowserType: '${device['defaultBrowserType']}'
        )''';
          })
          .join(',\n    ');

      // Build named variables that reference the map entries for ergonomic imports
      String sanitize(String name) {
        // Replace non-word characters with underscores and collapse repeats
        final sanitized = name
            .replaceAll(RegExp(r"[^A-Za-z0-9]+"), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_+|_+ '), '');
        // Ensure starts with a letter by prefixing with 'device_' if necessary
        final startsWithLetter = RegExp(r'^[A-Za-z]').hasMatch(sanitized);
        final base = startsWithLetter ? sanitized : 'device_$sanitized';
        // LowerCamelCase style: split by '_' then camelcase
        final parts = base.split('_');
        final camel =
            parts.first.toLowerCase() +
            parts
                .skip(1)
                .map(
                  (p) => p.isEmpty
                      ? ''
                      : (p[0].toUpperCase() + p.substring(1).toLowerCase()),
                )
                .join();
        return camel;
      }

      final devicesMapAssignments =
          '''
final devicesJsonData = {
  $devices
};
''';

      // Generate friendly top-level variables re-exporting devices by sanitized names
      final deviceVars = StringBuffer();
      json.forEach((key, value) {
        final varName = sanitize(key);
        deviceVars.writeln("final Device $varName = devicesJsonData['$key']!;");
      });

      final dartContent =
          '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated at: ${DateTime.now().toIso8601String()}

import 'device_json.dart';

$devicesMapAssignments

// Ergonomic named variables for direct import without map lookup
${deviceVars.toString()}
''';

      log.info('Writing to ${outputId.path}');
      await buildStep.writeAsString(outputId, dartContent);
      log.info('Successfully wrote devices_json_const.dart');
    } catch (e, stack) {
      log.severe('Error in device json builder: $e\n$stack');
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
    'lib/src/browser/bootstrap/device_json.dart': [
      'lib/src/browser/bootstrap/devices_json_const.dart',
    ],
  };
}
