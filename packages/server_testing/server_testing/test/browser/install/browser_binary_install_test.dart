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
        final registry = Registry(browserJsonData);
        final firefox = registry.getExecutable('firefox');
        final chromium = registry.getExecutable('chromium');

        expect(firefox, isNotNull);
        expect(chromium, isNotNull);

        if (firefox != null) {
          final pathStr = p.join(firefox.directory!, firefox.executablePath());
          expect(
            await File(pathStr).exists(),
            isTrue,
            reason: 'Firefox binary should exist at $pathStr',
          );
        }
        if (chromium != null) {
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
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
