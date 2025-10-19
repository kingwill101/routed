import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/src/browser/bootstrap/browsers_json_const.dart';
import 'package:server_testing/src/browser/bootstrap/driver/driver_manager.dart'
    as bootstrap_driver;
import 'package:server_testing/src/browser/bootstrap/registry.dart';

void main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  switch (args.first) {
    case 'install':
      final force = args.contains('--force') || args.contains('-f');
      final filtered = args.where((a) => a != '--force' && a != '-f').toList();
      final targets = filtered.length > 1
          ? filtered.sublist(1)
          : browserJsonData.browsers
                .where((b) => b.installByDefault)
                .map((b) => b.name)
                .toList();
      for (final name in targets) {
        stdout.writeln(
          'Ensuring installation for: $name${force ? ' (force)' : ''}',
        );
        try {
          // Build a registry on-demand for CLI
          final registry = Registry(browserJsonData);
          final exec = registry.getExecutable(name);
          if (exec == null) {
            throw Exception('Unknown browser executable: $name');
          }
          await registry.installExecutables([exec], force: force);
          stdout.writeln('$name is installed.');
        } catch (e) {
          stderr.writeln('Failed to install $name: $e');
          exitCode = 1;
        }
      }
      break;

    case 'install:driver':
      final force = args.contains('--force') || args.contains('-f');
      final filtered = args.where((a) => a != '--force' && a != '-f').toList();
      // browser name matches: chrome, firefox
      final targets = filtered.length > 1 ? filtered.sublist(1) : ['firefox'];
      for (final browser in targets) {
        stdout.writeln(
          'Ensuring driver for: $browser${force ? ' (force)' : ''}',
        );
        try {
          final port = await bootstrap_driver.DriverManager.ensureDriver(
            browser,
            force: force,
          );
          stdout.writeln('Driver for $browser ready on port $port');
        } catch (e) {
          stderr.writeln('Failed to setup driver for $browser: $e');
          exitCode = 1;
        }
      }
      break;

    case 'init':
      await _initProject();
      break;

    case 'create:browser':
    case 'create:browser-test':
      if (args.length < 2) {
        stderr.writeln(
          'Please provide a test name, e.g. create:browser home_page',
        );
        exit(64);
      }
      await _createBrowserTest(args[1]);
      break;

    case 'create:http':
    case 'create:http-test':
      if (args.length < 2) {
        stdout.writeln(
          '  install:driver [chrome|firefox]  Setup only the driver server [--force|-f]',
        );
        stderr.writeln(
          'Please provide a test name, e.g. create:http users_api',
        );
        exit(64);
      }
      await _createHttpTest(args[1]);
      break;

    default:
      _printUsage();
      exit(64);
  }
}

void _printUsage() {
  stdout.writeln('server_testing CLI');
  stdout.writeln('Usage: dart run server_testing <command> [args]');
  stdout.writeln('Commands:');
  stdout.writeln(
    '  install [browserNames...]   Install/verify browsers (default from browsers.json) [--force|-f]',
  );
  stdout.writeln(
    '  init                        Scaffold test config (browsers.json, test dirs)',
  );
  stdout.writeln(
    '  create:browser <name>       Create a browser test in test/browser/<name>_test.dart',
  );
  stdout.writeln(
    '  create:http <name>          Create an HTTP test in test/http/<name>_test.dart',
  );
}

Future<void> _initProject() async {
  // Create test directories
  final testDir = Directory('test');
  final browserDir = Directory(p.join('test', 'browser'));
  final httpDir = Directory(p.join('test', 'http'));
  await Future.wait([
    for (final d in [testDir, browserDir, httpDir]) d.create(recursive: true),
  ]);

  // Write example browsers.json if not present
  final browsersJson = File('browsers.json');
  if (!await browsersJson.exists()) {
    await browsersJson.writeAsString(_defaultBrowsersJson);
    stdout.writeln('Created browsers.json');
  } else {
    stdout.writeln('browsers.json already exists, skipping');
  }

  // Create example test files if not present
  final exampleBrowser = File(p.join(browserDir.path, 'example_test.dart'));
  if (!await exampleBrowser.exists()) {
    await exampleBrowser.writeAsString(_exampleBrowserTest);
    stdout.writeln('Created ${exampleBrowser.path}');
  }

  final exampleHttp = File(p.join(httpDir.path, 'example_test.dart'));
  if (!await exampleHttp.exists()) {
    await exampleHttp.writeAsString(_exampleHttpTest);
    stdout.writeln('Created ${exampleHttp.path}');
  }

  stdout.writeln('Initialization complete. Run `dart test` to execute tests.');
}

Future<void> _createBrowserTest(String name) async {
  final fileName = '${_sanitize(name)}_test.dart';
  final file = File(p.join('test', 'browser', fileName))
    ..createSync(recursive: true);
  await file.writeAsString(_exampleBrowserTest);
  stdout.writeln('Created ${file.path}');
}

Future<void> _createHttpTest(String name) async {
  final fileName = '${_sanitize(name)}_test.dart';
  final file = File(p.join('test', 'http', fileName))
    ..createSync(recursive: true);
  await file.writeAsString(_exampleHttpTest);
  stdout.writeln('Created ${file.path}');
}

String _sanitize(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll(RegExp(r'[^a-z0-9_]+'), '');

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
