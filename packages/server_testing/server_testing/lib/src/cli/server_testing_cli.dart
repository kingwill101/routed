import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:artisanal/tui.dart';
import 'package:path/path.dart' as p;
import 'package:server_testing/src/browser/bootstrap/browser_json.dart';
import 'package:server_testing/src/browser/bootstrap/browser_paths.dart';
import 'package:server_testing/src/browser/bootstrap/browsers_json_const.dart';
import 'package:server_testing/src/browser/bootstrap/downloader.dart';
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
  }) : _browsersJson = browsersJson,
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr,
       _workingDirectory = workingDirectory ?? Directory.current {
    _installBrowser = installBrowser ?? _defaultInstallBrowser;
    _installDriver = installDriver ?? _defaultInstallDriver;
  }

  final BrowserJson? _browsersJson;
  final StringSink _stdout;
  final StringSink _stderr;
  final Directory _workingDirectory;

  late final BrowserInstaller _installBrowser;
  late final DriverInstaller _installDriver;
  Registry? _registry;
  BrowserJson? _loadedBrowsersJson;

  Future<void> _defaultInstallBrowser(String name, {bool force = false}) async {
    _registry ??= await _ensureRegistry();
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
    if (args.isEmpty) {
      _buildRunner().printUsage();
      return 0;
    }
    if (args.length == 1 && (args[0] == '--help' || args[0] == '-h')) {
      _buildRunner().printUsage();
      return 0;
    }

    int? usageExitCode;
    final runner = _buildRunner(
      setExitCode: (code) {
        usageExitCode = code;
      },
    );

    try {
      final result = await runner.run(args);
      if (result != null) return result;
      return usageExitCode ?? 0;
    } catch (e) {
      _stderr.writeln('Failed to run command: $e');
      return 1;
    }
  }

  Future<int> _handleInstall(
    List<String> targets, {
    required bool force,
  }) async {
    final effectiveTargets = targets.isNotEmpty
        ? targets
        : (await _ensureRegistry()).defaultExecutables
              .map((e) => e.name)
              .toList();

    var exitCode = 0;
    for (final name in effectiveTargets) {
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

  Future<int> _handleInstallDriver(
    List<String> targets, {
    required bool force,
  }) async {
    final effectiveTargets = targets.isNotEmpty ? targets : ['firefox'];

    var exitCode = 0;
    for (final browser in effectiveTargets) {
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

  CommandRunner<int> _buildRunner({void Function(int code)? setExitCode}) {
    final runner = CommandRunner<int>(
      'dart run server_testing',
      'server_testing CLI',
      usageExitCode: 64,
      out: (line) => _stdout.writeln(line),
      err: (line) => _stderr.writeln(line),
      setExitCode: setExitCode,
    );
    runner
      ..addCommand(_InstallCommand(this))
      ..addCommand(_InstallDriverCommand(this))
      ..addCommand(_InitCommand(this))
      ..addCommand(_CreateBrowserCommand(this))
      ..addCommand(_CreateHttpCommand(this));
    return runner;
  }

  Future<Registry> _ensureRegistry() async {
    if (_registry != null) return _registry!;
    _configureProgressRenderer();
    final browsersJson = await _loadBrowsersJson();
    _stdout.writeln(
      'Using browser cache directory: ${BrowserPaths.getRegistryDirectory()}',
    );
    _registry = Registry(browsersJson);
    return _registry!;
  }

  void _configureProgressRenderer() {
    if (_stdout != stdout || !stdout.hasTerminal) return;
    if (Platform.environment['SERVER_TESTING_TUI'] == '0') return;
    if (Registry.progressRenderer != null) return;

    final progressBar = ProgressModel(
      width: 28,
      full: '=',
      empty: '-',
      showPercentage: false,
      useGradient: false,
    );

    Registry.progressRenderer = (DownloadProgress progress) {
      final total = progress.total;
      final percent = total > 0 ? progress.received / total : 0.0;
      final bar = progressBar.viewAs(percent);
      final mb = (progress.received / 1024 / 1024).toStringAsFixed(1);
      final totalMb = total > 0
          ? (total / 1024 / 1024).toStringAsFixed(1)
          : '?';
      final mbps = (progress.speed / 1024 / 1024).toStringAsFixed(1);
      stdout.write('\r$bar $mb/$totalMb MB @ $mbps MB/s'.padRight(80));
    };
  }

  Future<BrowserJson> _loadBrowsersJson() async {
    if (_loadedBrowsersJson != null) return _loadedBrowsersJson!;
    if (_browsersJson != null) {
      _loadedBrowsersJson = _browsersJson;
      return _loadedBrowsersJson!;
    }

    final jsonPath = p.join(_workingDirectory.path, 'browsers.json');
    final file = File(jsonPath);
    if (!await file.exists()) {
      _stdout.writeln(
        'No browsers.json found at $jsonPath, using embedded defaults.',
      );
      _loadedBrowsersJson = browserJsonData;
      return _loadedBrowsersJson!;
    }

    final content = await file.readAsString();
    _stdout.writeln('Loaded browsers.json from $jsonPath');
    _loadedBrowsersJson = BrowserJson.fromJson(
      json.decode(content) as Map<String, dynamic>,
    );
    return _loadedBrowsersJson!;
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
    );
    file.parent.createSync(recursive: true);
    file.createSync();
    await file.writeAsString(_exampleBrowserTest);
    _stdout.writeln('Created ${file.path}');
  }

  Future<void> _createHttpTest(String name) async {
    final fileName = '${_sanitize(name)}_test.dart';
    final file = File(p.join(_workingDirectory.path, 'test', 'http', fileName));
    file.parent.createSync(recursive: true);
    file.createSync();
    await file.writeAsString(_exampleHttpTest);
    _stdout.writeln('Created ${file.path}');
  }

  String _sanitize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '');
}

class _InstallCommand extends Command<int> {
  _InstallCommand(this._cli) {
    argParser.addFlag('force', abbr: 'f', negatable: false);
  }

  final ServerTestingCli _cli;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install/verify browsers (default from browsers.json).';

  @override
  Future<int> run() async {
    if (argResults?['help'] as bool? ?? false) {
      printUsage();
      return 0;
    }
    final force = argResults?['force'] as bool? ?? false;
    final targets = argResults?.rest ?? const <String>[];
    return _cli._handleInstall(targets, force: force);
  }
}

class _InstallDriverCommand extends Command<int> {
  _InstallDriverCommand(this._cli) {
    argParser.addFlag('force', abbr: 'f', negatable: false);
  }

  final ServerTestingCli _cli;

  @override
  String get name => 'install:driver';

  @override
  String get description => 'Setup WebDriver binaries (default: firefox).';

  @override
  Future<int> run() async {
    if (argResults?['help'] as bool? ?? false) {
      printUsage();
      return 0;
    }
    final force = argResults?['force'] as bool? ?? false;
    final targets = argResults?.rest ?? const <String>[];
    return _cli._handleInstallDriver(targets, force: force);
  }
}

class _InitCommand extends Command<int> {
  _InitCommand(this._cli);

  final ServerTestingCli _cli;

  @override
  String get name => 'init';

  @override
  String get description => 'Scaffold test config (browsers.json, test dirs).';

  @override
  Future<int> run() async {
    if (argResults?['help'] as bool? ?? false) {
      printUsage();
      return 0;
    }
    await _cli._initProject();
    return 0;
  }
}

class _CreateBrowserCommand extends Command<int> {
  _CreateBrowserCommand(this._cli)
    : super(aliases: const ['create:browser-test']);

  final ServerTestingCli _cli;

  @override
  String get name => 'create:browser';

  @override
  String get description =>
      'Create a browser test in test/browser/<name>_test.dart.';

  @override
  Future<int> run() async {
    if (argResults?['help'] as bool? ?? false) {
      printUsage();
      return 0;
    }
    final name = _joinedName(argResults?.rest ?? const <String>[]);
    if (name.isEmpty) {
      _cli._stderr.writeln(
        'Please provide a test name, e.g. create:browser home_page',
      );
      return 64;
    }
    await _cli._createBrowserTest(name);
    return 0;
  }
}

class _CreateHttpCommand extends Command<int> {
  _CreateHttpCommand(this._cli) : super(aliases: const ['create:http-test']);

  final ServerTestingCli _cli;

  @override
  String get name => 'create:http';

  @override
  String get description =>
      'Create an HTTP test in test/http/<name>_test.dart.';

  @override
  Future<int> run() async {
    if (argResults?['help'] as bool? ?? false) {
      printUsage();
      return 0;
    }
    final name = _joinedName(argResults?.rest ?? const <String>[]);
    if (name.isEmpty) {
      _cli._stderr.writeln(
        'Please provide a test name, e.g. create:http users_api',
      );
      return 64;
    }
    await _cli._createHttpTest(name);
    return 0;
  }
}

String _joinedName(List<String> parts) => parts.join(' ').trim();

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
