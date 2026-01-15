import 'dart:io';

import 'package:server_testing/src/browser/bootstrap/browser_json.dart';
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

        Future<void> ensureBinary(
          Registry registry,
          String browserName,
          Executable executable,
        ) async {
          final override = binaryOverrideFor(browserName);
          if (override != null) {
            expect(
              await File(override).exists(),
              isTrue,
              reason: '$browserName override binary should exist at $override',
            );
            return;
          }

          final pathStr = executable.executablePath();
          if (!await File(pathStr).exists()) {
            await registry.installExecutables([executable], force: true);
          }

          expect(
            await File(pathStr).exists(),
            isTrue,
            reason: '$browserName binary should exist at $pathStr',
          );
        }

        final registry = Registry(browserJsonData);
        final firefox = registry.getExecutable('firefox');
        final chromium = registry.getExecutable('chromium');

        expect(firefox, isNotNull);
        expect(chromium, isNotNull);

        if (firefox != null) {
          await ensureBinary(registry, 'firefox', firefox);
        }
        if (chromium != null) {
          await ensureBinary(registry, 'chromium', chromium);
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }, tags: ['real-browser']);
}
