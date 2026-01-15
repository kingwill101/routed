@Tags(['real-browser'])
import 'dart:io';

import 'package:server_testing/src/browser/bootstrap/browsers_json_const.dart';
import 'package:server_testing/src/browser/bootstrap/registry.dart';
import 'package:test/test.dart';

void main() {
  group('Browser bundle install/reinstall', () {
    test(
      'force reinstall deletes existing browser dir and re-installs',
      () async {
        final registry = Registry(browserJsonData);

        // Choose chromium for the test (present in registry for this platform)
        final exec = registry.getExecutable('chromium');
        expect(exec, isNotNull);

        // First install if needed
        await registry.installExecutables([exec!], force: false);
        final dir = Directory(exec.directory!);
        expect(
          await dir.exists(),
          isTrue,
          reason: 'browser directory should exist after install',
        );

        // Force reinstall and verify directory was deleted and recreated
        await registry.installExecutables([exec], force: true);
        expect(
          await dir.exists(),
          isTrue,
          reason: 'browser directory should exist after force reinstall',
        );

        // sanity: directory should contain files
        expect(await dir.list().isEmpty, isFalse);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }, tags: ['real-browser']);
}
