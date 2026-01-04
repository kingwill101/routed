import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/src/browser/bootstrap/browser_json.dart';
import 'package:server_testing/src/browser/bootstrap/browsers_json_const.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as bootstrap_driver;
import 'package:server_testing/src/browser/bootstrap/registry.dart';

typedef BrowserInstaller = Future<void> Function(String name, {bool force});
typedef DriverInstaller = Future<int> Function(String browser, {bool force});

class ServerTestingCli {
  ServerTestingCli({
    BrowserJson? browsersJson,
    BrowserInstaller? installBrowser,
    DriverInstaller? installDriver,
    StringSink? stdoutSink,
    StringSink? stderrSink,
    Directory? workingDirectory,
  }) : _browsersJson = browsersJson ?? browserJsonData,
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr,
       _workingDirectory = workingDirectory ?? Directory.current {
    _installBrowser = installBrowser ?? _defaultInstallBrowser;
    _installDriver = installDriver ?? _defaultInstallDriver;
  }

  final BrowserJson _browsersJson;
  final StringSink _stdout;
  final StringSink _stderr;
  final Directory _workingDirectory;

  late final BrowserInstaller _installBrowser;
  late final DriverInstaller _installDriver;
  Registry? _registry;

  Future<void> _defaultInstallBrowser(String name, {bool force = false}) async {
    _registry ??= Registry(_browsersJson);
    final exec = _registry!.getExecutable(name);
    if (exec == null) {
      throw Exception('Unknown browser executable: $name');
    }
    await _registry!.installExecutables([exec], force: force);
  }

  Future<int> _defaultInstallDriver(String browser, {bool force = false}) {
    return bootstrap_driver.DriverManager.ensureDriver(browser, force: force);
  }

  Future<int> run(List<String> args) async {
    if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return 0;
    }

    switch (args.first) {
      case 'install':
        return _handleInstall(args);
      case 'install:driver':
        return _handleInstallDriver(args);
      case 'init':
        await _initProject();
        return 0;
      case 'create:browser':
      case 'create:browser-test':
        if (args.length < 2) {
          _stderr.writeln(
            'Please provide a test name, e.g. create:browser home_page',
          );
          return 64;
        }
        await _createBrowserTest(args[1]);
        return 0;
      case 'create:http':
      case 'create:http-test':
        if (args.length < 2) {
          _stderr.writeln(
            'Please provide a test name, e.g. create:http users_api',
          );
          return 64;
        }
        await _createHttpTest(args[1]);
        return 0;
      default:
        _printUsage();
        return 64;
    }
  }

  Future<int> _handleInstall(List<String> args) async {
    final force = args.contains('--force') || args.contains('-f');
    final filtered = args.where((a) => a != '--force' && a != '-f').toList();
    final targets = filtered.length > 1
        ? filtered.sublist(1)
        : _browsersJson.browsers
              .where((b) => b.installByDefault)
              .map((b) => b.name)
              .toList();

    var exitCode = 0;
    for (final name in targets) {
      _stdout.writeln(
        'Ensuring installation for: $name${force ? ' (force)' : ''}',
      );
      try {
        await _installBrowser(name, force: force);
        _stdout.writeln('$name is installed.');
      } catch (e) {
        _stderr.writeln('Failed to install $name: $e');
        exitCode = 1;
      }
    }

    return exitCode;
  }

  Future<int> _handleInstallDriver(List<String> args) async {
    final force = args.contains('--force') || args.contains('-f');
    final filtered = args.where((a) => a != '--force' && a != '-f').toList();
    final targets = filtered.length > 1 ? filtered.sublist(1) : ['firefox'];

    var exitCode = 0;
    for (final browser in targets) {
      _stdout.writeln(
        'Ensuring driver for: $browser${force ? ' (force)' : ''}',
      );
      try {
        final port = await _installDriver(browser, force: force);
        _stdout.writeln('Driver for $browser ready on port $port');
      } catch (e) {
        _stderr.writeln('Failed to setup driver for $browser: $e');
        exitCode = 1;
      }
    }

    return exitCode;
  }

  void _printUsage() {
    _stdout.writeln('server_testing CLI');
    _stdout.writeln('Usage: dart run server_testing <command> [args]');
    _stdout.writeln('Commands:');
    _stdout.writeln(
      '  install [browserNames...]   Install/verify browsers (default from browsers.json) [--force|-f]',
    );
    _stdout.writeln(
      '  install:driver [browser]    Setup WebDriver binaries (default: firefox) [--force|-f]',
    );
    _stdout.writeln(
      '  init                        Scaffold test config (browsers.json, test dirs)',
    );
    _stdout.writeln(
      '  create:browser <name>       Create a browser test in test/browser/<name>_test.dart',
    );
    _stdout.writeln(
      '  create:http <name>          Create an HTTP test in test/http/<name>_test.dart',
    );
  }

  Future<void> _initProject() async {
    final testDir = Directory(p.join(_workingDirectory.path, 'test'));
    final browserDir = Directory(
      p.join(_workingDirectory.path, 'test', 'browser'),
    );
    final httpDir = Directory(p.join(_workingDirectory.path, 'test', 'http'));
    await Future.wait([
      for (final d in [testDir, browserDir, httpDir]) d.create(recursive: true),
    ]);

    final browsersJson = File(p.join(_workingDirectory.path, 'browsers.json'));
    if (!await browsersJson.exists()) {
      await browsersJson.writeAsString(_defaultBrowsersJson);
      _stdout.writeln('Created browsers.json');
    } else {
      _stdout.writeln('browsers.json already exists, skipping');
    }

    final exampleBrowser = File(p.join(browserDir.path, 'example_test.dart'));
    if (!await exampleBrowser.exists()) {
      await exampleBrowser.writeAsString(_exampleBrowserTest);
      _stdout.writeln('Created ${exampleBrowser.path}');
    }

    final exampleHttp = File(p.join(httpDir.path, 'example_test.dart'));
    if (!await exampleHttp.exists()) {
      await exampleHttp.writeAsString(_exampleHttpTest);
      _stdout.writeln('Created ${exampleHttp.path}');
    }

    _stdout.writeln(
      'Initialization complete. Run `dart test` to execute tests.',
    );
  }

  Future<void> _createBrowserTest(String name) async {
    final fileName = '${_sanitize(name)}_test.dart';
    final file = File(
      p.join(_workingDirectory.path, 'test', 'browser', fileName),
    )..createSync(recursive: true);
    await file.writeAsString(_exampleBrowserTest);
    _stdout.writeln('Created ${file.path}');
  }

  Future<void> _createHttpTest(String name) async {
    final fileName = '${_sanitize(name)}_test.dart';
    final file = File(p.join(_workingDirectory.path, 'test', 'http', fileName))
      ..createSync(recursive: true);
    await file.writeAsString(_exampleHttpTest);
    _stdout.writeln('Created ${file.path}');
  }

  String _sanitize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '');
}

const _defaultBrowsersJson = r'''
{
  "browsers": [
    { "name": "firefox", "installByDefault": true },
    { "name": "chromium", "installByDefault": false }
  ]
}
''';

const _exampleBrowserTest = r'''
import 'package:test/test.dart';
import 'package:server_testing/server_testing.dart';

void main() async {
  await testBootstrap(BrowserConfig(
    browserName: 'firefox',
    headless: true,
    baseUrl: 'https://example.com',
    verbose: false,
  ));

  browserTest('homepage shows title', (browser) async {
    await browser.visit('/');
    await browser.assertTitle('Example Domain');
  });
}
''';

const _exampleHttpTest = r'''
import 'package:test/test.dart';
import 'package:server_testing/server_testing.dart';

class EchoHandler implements RequestHandler {
  @override
  Future<void> handleRequest(HttpRequest request) async {
    final response = request.response;
    response.statusCode = 200;
    response.headers.contentType = ContentType.json;
    response.write('{"ok": true}');
    await response.close();
  }

  @override
  Future<int> startServer({int port = 0}) async => 0;

  @override
  Future<void> close([bool force = true]) async {}
}

void main() {
  serverTest('echo ok', (client) async {
    final res = await client.get('/');
    res.assertStatus(200).assertJson((json) => json.where('ok', true));
  }, handler: EchoHandler());
}
''';
