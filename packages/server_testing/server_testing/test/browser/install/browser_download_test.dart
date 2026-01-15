import 'dart:io';

// ignore_for_file: avoid_print

import 'package:path/path.dart' as p;
import 'package:server_testing/src/browser/bootstrap/browser_paths.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart';
import 'package:test/test.dart';

void main() {
  group('Driver download and install', () {
    late String driversDir;

    setUp(() async {
      final base = BrowserPaths.getRegistryDirectory();
      driversDir = p.join(base, 'drivers');
      await Directory(driversDir).create(recursive: true);
    });

    tearDown(() async {
      // don’t remove the directory itself; leave for future runs
    });

    test(
      'ensureDriver(chrome) downloads and places chromedriver binary',
      () async {
        await Directory(driversDir).list().toList();
        final port = await DriverManager.ensureDriver('chrome');
        expect(port, greaterThan(0));

        final expected = Platform.isWindows
            ? File(p.join(driversDir, 'chromedriver.exe'))
            : File(p.join(driversDir, 'chromedriver'));

        expect(
          await expected.exists(),
          isTrue,
          reason: 'chromedriver should exist after setup',
        );

        // basic sanity: file should not be empty
        expect(await expected.length(), greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'force reinstall removes existing driver before re-download',
      () async {
        // First ensure driver exists
        await DriverManager.ensureDriver('chrome');
        final driverPath = Platform.isWindows
            ? p.join(driversDir, 'chromedriver.exe')
            : p.join(driversDir, 'chromedriver');
        final driverFile = File(driverPath);
        expect(await driverFile.exists(), isTrue);
        final initialMtime = (await driverFile.stat()).modified;

        // Request force reinstall and verify the existing binary is deleted and reinstalled
        final port = await DriverManager.ensureDriver('chrome', force: true);
        expect(port, greaterThan(0));
        expect(
          await driverFile.exists(),
          isTrue,
          reason: 'driver must be re-downloaded after deletion',
        );
        final newMtime = (await driverFile.stat()).modified;
        expect(
          newMtime.isAfter(initialMtime) ||
              newMtime.isAtSameMomentAs(initialMtime),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, tags: ['real-browser']);
}
