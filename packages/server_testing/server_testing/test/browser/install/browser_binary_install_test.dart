import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/src/browser/bootstrap/browsers_json_const.dart';
import 'package:server_testing/src/browser/bootstrap/registry.dart';
import 'package:test/test.dart';

void main() {
  group('Browser binary installation', () {
    test(
      'registry executable path exists for firefox and chromium',
      () async {
        String? binaryOverrideFor(String browserName) {
          final normalized = browserName.toUpperCase().replaceAll('-', '_');
          final overrides = <String>['SERVER_TESTING_${normalized}_BINARY'];
          if (browserName == 'chromium') {
            overrides.add('SERVER_TESTING_CHROME_BINARY');
          }
          for (final key in overrides) {
            final value = Platform.environment[key];
            if (value != null && value.trim().isNotEmpty) {
              return value.trim();
            }
          }
          return null;
        }

        final registry = Registry(browserJsonData);
        final firefox = registry.getExecutable('firefox');
        final chromium = registry.getExecutable('chromium');

        expect(firefox, isNotNull);
        expect(chromium, isNotNull);

        if (firefox != null) {
          final override = binaryOverrideFor('firefox');
          if (override != null) {
            expect(
              await File(override).exists(),
              isTrue,
              reason: 'Firefox override binary should exist at $override',
            );
          } else {
            final pathStr = p.join(
              firefox.directory!,
              firefox.executablePath(),
            );
            expect(
              await File(pathStr).exists(),
              isTrue,
              reason: 'Firefox binary should exist at $pathStr',
            );
          }
        }
        if (chromium != null) {
          final override = binaryOverrideFor('chromium');
          if (override != null) {
            expect(
              await File(override).exists(),
              isTrue,
              reason: 'Chromium override binary should exist at $override',
            );
          } else {
            final pathStr = p.join(
              chromium.directory!,
              chromium.executablePath(),
            );
            expect(
              await File(pathStr).exists(),
              isTrue,
              reason: 'Chromium binary should exist at $pathStr',
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
