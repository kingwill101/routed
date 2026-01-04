import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/src/browser/bootstrap/browser_json.dart';
import 'package:server_testing/src/cli/server_testing_cli.dart';
import 'package:test/test.dart';

class _Call {
  _Call(this.target, this.force);

  final String target;
  final bool force;
}

class _FakeInstallers {
  final browserCalls = <_Call>[];
  final driverCalls = <_Call>[];

  Future<void> installBrowser(String name, {bool force = false}) async {
    browserCalls.add(_Call(name, force));
    if (name == 'bad') {
      throw Exception('bad browser');
    }
  }

  Future<int> installDriver(String browser, {bool force = false}) async {
    driverCalls.add(_Call(browser, force));
    if (browser == 'bad') {
      throw Exception('bad driver');
    }
    return 4444;
  }
}

BrowserJson _sampleBrowsers() {
  return BrowserJson(
    comment: 'test',
    browsers: [
      BrowserEntry(name: 'firefox', revision: '1', installByDefault: true),
      BrowserEntry(name: 'chromium', revision: '2', installByDefault: false),
    ],
  );
}

void main() {
  test('prints usage on help', () async {
    final out = StringBuffer();
    final err = StringBuffer();

    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: _sampleBrowsers(),
    );

    final exit = await cli.run(['--help']);

    expect(exit, 0);
    expect(out.toString(), contains('server_testing CLI'));
    expect(out.toString(), contains('Usage:'));
    expect(err.toString(), isEmpty);
  });

  test('unknown command returns usage error', () async {
    final out = StringBuffer();
    final err = StringBuffer();

    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: _sampleBrowsers(),
    );

    final exit = await cli.run(['wat']);

    expect(exit, 64);
    expect(out.toString(), contains('Usage:'));
    expect(err.toString(), contains('Error:'));
  });

  test('init creates default scaffold', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final out = StringBuffer();
    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['init']);

    expect(exit, 0);
    expect(
      Directory(p.join(tempDir.path, 'test', 'browser')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(tempDir.path, 'test', 'http')).existsSync(),
      isTrue,
    );
    expect(File(p.join(tempDir.path, 'browsers.json')).existsSync(), isTrue);
    expect(
      File(
        p.join(tempDir.path, 'test', 'browser', 'example_test.dart'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(tempDir.path, 'test', 'http', 'example_test.dart'),
      ).existsSync(),
      isTrue,
    );
  });

  test('create:browser writes sanitized file', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final out = StringBuffer();
    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['create:browser', 'Home Page']);

    expect(exit, 0);
    final expected = File(
      p.join(tempDir.path, 'test', 'browser', 'home_page_test.dart'),
    );
    expect(expected.existsSync(), isTrue);
    expect(expected.readAsStringSync(), contains('browserTest'));
  });

  test('create:http writes sanitized file', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final out = StringBuffer();
    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['create:http', 'Users API']);

    expect(exit, 0);
    final expected = File(
      p.join(tempDir.path, 'test', 'http', 'users_api_test.dart'),
    );
    expect(expected.existsSync(), isTrue);
    expect(expected.readAsStringSync(), contains('serverTest'));
  });

  test('create:browser requires a name', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final out = StringBuffer();
    final err = StringBuffer();
    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['create:browser']);

    expect(exit, 64);
    expect(err.toString(), contains('Please provide a test name'));
    expect(
      Directory(p.join(tempDir.path, 'test', 'browser')).existsSync(),
      isFalse,
    );
  });

  test('create:browser-test alias writes sanitized file', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final cli = ServerTestingCli(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['create:browser-test', 'Home Page']);

    expect(exit, 0);
    final expected = File(
      p.join(tempDir.path, 'test', 'browser', 'home_page_test.dart'),
    );
    expect(expected.existsSync(), isTrue);
  });

  test('create:http-test alias writes sanitized file', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final cli = ServerTestingCli(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['create:http-test', 'Users API']);

    expect(exit, 0);
    final expected = File(
      p.join(tempDir.path, 'test', 'http', 'users_api_test.dart'),
    );
    expect(expected.existsSync(), isTrue);
  });

  test('create sanitizes punctuation and case', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final cli = ServerTestingCli(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['create:browser', 'API v2!!']);

    expect(exit, 0);
    final expected = File(
      p.join(tempDir.path, 'test', 'browser', 'api_v2_test.dart'),
    );
    expect(expected.existsSync(), isTrue);
  });

  test('init does not overwrite existing files', () async {
    final tempDir = await Directory.systemTemp.createTemp('server-testing');
    addTearDown(() => tempDir.delete(recursive: true));

    final testDir = Directory(p.join(tempDir.path, 'test'));
    final browserDir = Directory(p.join(tempDir.path, 'test', 'browser'));
    final httpDir = Directory(p.join(tempDir.path, 'test', 'http'));
    await Future.wait([
      testDir.create(recursive: true),
      browserDir.create(recursive: true),
      httpDir.create(recursive: true),
    ]);

    final browsersJson = File(p.join(tempDir.path, 'browsers.json'));
    await browsersJson.writeAsString('{"browsers": []}');

    final browserExample = File(p.join(browserDir.path, 'example_test.dart'));
    final httpExample = File(p.join(httpDir.path, 'example_test.dart'));
    await browserExample.writeAsString('browser placeholder');
    await httpExample.writeAsString('http placeholder');

    final out = StringBuffer();
    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      workingDirectory: tempDir,
    );

    final exit = await cli.run(['init']);

    expect(exit, 0);
    expect(out.toString(), contains('browsers.json already exists, skipping'));
    expect(browserExample.readAsStringSync(), 'browser placeholder');
    expect(httpExample.readAsStringSync(), 'http placeholder');
  });

  test('install uses defaults and respects force', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final installers = _FakeInstallers();

    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: _sampleBrowsers(),
      installBrowser: installers.installBrowser,
      installDriver: installers.installDriver,
    );

    final exit = await cli.run(['install', 'chromium', '--force']);

    expect(exit, 0);
    expect(installers.browserCalls, hasLength(1));
    expect(installers.browserCalls.first.target, 'chromium');
    expect(installers.browserCalls.first.force, isTrue);
  });

  test('install default browsers', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final installers = _FakeInstallers();

    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: _sampleBrowsers(),
      installBrowser: installers.installBrowser,
      installDriver: installers.installDriver,
    );

    final exit = await cli.run(['install']);

    expect(exit, 0);
    expect(installers.browserCalls, hasLength(1));
    expect(installers.browserCalls.first.target, 'firefox');
  });

  test('install continues after failures', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final installers = _FakeInstallers();

    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: BrowserJson(
        comment: 'test',
        browsers: [
          BrowserEntry(name: 'bad', revision: '1', installByDefault: true),
          BrowserEntry(name: 'firefox', revision: '2', installByDefault: true),
        ],
      ),
      installBrowser: installers.installBrowser,
      installDriver: installers.installDriver,
    );

    final exit = await cli.run(['install']);

    expect(exit, 1);
    expect(installers.browserCalls, hasLength(2));
    expect(installers.browserCalls.first.target, 'bad');
    expect(installers.browserCalls.last.target, 'firefox');
    expect(err.toString(), contains('Failed to install bad'));
  });

  test('install:driver defaults to firefox', () async {
    final installers = _FakeInstallers();

    final cli = ServerTestingCli(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      installBrowser: installers.installBrowser,
      installDriver: installers.installDriver,
    );

    final exit = await cli.run(['install:driver']);

    expect(exit, 0);
    expect(installers.driverCalls, hasLength(1));
    expect(installers.driverCalls.first.target, 'firefox');
  });

  test('install:driver respects force flag and multiple targets', () async {
    final installers = _FakeInstallers();

    final cli = ServerTestingCli(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      browsersJson: _sampleBrowsers(),
      installBrowser: installers.installBrowser,
      installDriver: installers.installDriver,
    );

    final exit = await cli.run(['install:driver', 'chrome', 'firefox', '--force']);

    expect(exit, 0);
    expect(installers.driverCalls, hasLength(2));
    expect(installers.driverCalls.first.target, 'chrome');
    expect(installers.driverCalls.first.force, isTrue);
    expect(installers.driverCalls.last.target, 'firefox');
    expect(installers.driverCalls.last.force, isTrue);
  });

  test('install:driver reports failures', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final installers = _FakeInstallers();

    final cli = ServerTestingCli(
      stdoutSink: out,
      stderrSink: err,
      browsersJson: _sampleBrowsers(),
      installBrowser: installers.installBrowser,
      installDriver: installers.installDriver,
    );

    final exit = await cli.run(['install:driver', 'bad']);

    expect(exit, 1);
    expect(installers.driverCalls, hasLength(1));
    expect(err.toString(), contains('Failed to setup driver for bad'));
  });
}
