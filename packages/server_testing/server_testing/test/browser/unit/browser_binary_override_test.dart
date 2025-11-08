import 'dart:io';

import 'package:server_testing/src/browser/bootstrap/bootstrap.dart';
import 'package:server_testing/src/browser/browser_config.dart';
import 'package:server_testing/src/browser/browser_exception.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('st_override_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('ensureBrowserInstalled skips install when override exists', () async {
    final fakeBinary = File('${tempDir.path}/chromium');
    fakeBinary.createSync(recursive: true);

    await TestBootstrap.initialize(
      BrowserConfig(
        autoInstall: false,
        binaryOverrides: {'chromium': fakeBinary.path},
      ),
    );

    final installed = await TestBootstrap.ensureBrowserInstalled('chromium');
    expect(installed, isFalse);

    final resolved = await TestBootstrap.resolveExecutablePath('chromium');
    expect(resolved, fakeBinary.path);
  });

  test('override paths must exist', () async {
    final missingPath = '${tempDir.path}/missing-browser';

    await TestBootstrap.initialize(
      BrowserConfig(
        autoInstall: false,
        binaryOverrides: {'chromium': missingPath},
      ),
    );

    await expectLater(
      TestBootstrap.ensureBrowserInstalled('chromium'),
      throwsA(isA<BrowserException>()),
    );
  });

  test('aliases like chrome honor overrides', () async {
    final fakeBinary = File('${tempDir.path}/chrome-bin');
    fakeBinary.createSync(recursive: true);

    await TestBootstrap.initialize(
      BrowserConfig(
        autoInstall: false,
        binaryOverrides: {'chrome': fakeBinary.path},
      ),
    );

    final resolved = await TestBootstrap.resolveExecutablePath('chrome');
    expect(resolved, fakeBinary.path);
  });
}
