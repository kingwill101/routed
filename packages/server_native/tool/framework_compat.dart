import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_native/src/generated/prebuilt_release.g.dart';

/// Runs external framework compatibility suites against `server_native`.
///
/// The runner clones/updates target repositories, applies deterministic patches
/// from `tool/framework_compat/patches`, and executes tests in one or both
/// compatibility modes:
///
/// - `io`: framework uses `dart:io` `HttpServer`
/// - `native`: framework uses `server_native` `NativeHttpServer`
Future<void> main(List<String> args) async {
  final options = _CliOptions.parse(args);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final repoRoot = _findRepoRoot();
  final packageRoot = p.join(repoRoot.path, 'packages', 'server_native');
  final patchesRoot = p.join(
    packageRoot,
    'tool',
    'framework_compat',
    'patches',
  );
  final workspaceRoot = Directory(
    p.normalize(
      p.isAbsolute(options.workspaceRoot)
          ? options.workspaceRoot
          : p.join(repoRoot.path, options.workspaceRoot),
    ),
  );

  await workspaceRoot.create(recursive: true);

  final frameworks = <String, _FrameworkConfig>{
    'shelf': const _FrameworkConfig(
      name: 'shelf',
      gitUrl: 'https://github.com/dart-lang/shelf.git',
      branch: 'master',
      patchFile: 'shelf.patch',
    ),
    'relic': const _FrameworkConfig(
      name: 'relic',
      gitUrl: 'https://github.com/serverpod/relic.git',
      branch: 'main',
      patchFile: 'relic.patch',
    ),
    'serinus': const _FrameworkConfig(
      name: 'serinus',
      gitUrl: 'https://github.com/kingwill101/serinus.git',
      branch: 'feat/server_native',
      patchFile: 'serinus.patch',
    ),
  };

  final selectedFrameworks = options.frameworks.contains('all')
      ? frameworks.keys.toSet()
      : options.frameworks;
  final unknown = selectedFrameworks.difference(frameworks.keys.toSet());
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown framework(s): ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }

  stdout.writeln('repoRoot: ${repoRoot.path}');
  stdout.writeln('packageRoot: $packageRoot');
  stdout.writeln('workspaceRoot: ${workspaceRoot.path}');
  stdout.writeln('frameworks: ${selectedFrameworks.join(', ')}');
  stdout.writeln('modes: ${options.modes.map((m) => m.name).join(', ')}');

  final localPrebuiltLibrary = _findLocalNativeLibrary(packageRoot);
  if (localPrebuiltLibrary != null) {
    stdout.writeln('localPrebuilt: ${localPrebuiltLibrary.path}');
  } else {
    stdout.writeln('localPrebuilt: <none>');
  }

  final results = <_CommandResult>[];
  var hasFailures = false;

  for (final frameworkName in selectedFrameworks) {
    final framework = frameworks[frameworkName]!;
    final checkoutDir = Directory(p.join(workspaceRoot.path, framework.name));

    stdout.writeln('\n=== ${framework.name}: sync ===');
    await _syncRepo(
      framework: framework,
      checkoutDir: checkoutDir,
      fresh: options.fresh,
    );

    stdout.writeln('=== ${framework.name}: patch ===');
    await _applyPatch(
      framework: framework,
      checkoutDir: checkoutDir,
      patchFile: File(p.join(patchesRoot, framework.patchFile)),
      serverNativePath: p.normalize(packageRoot),
    );
    await _writeRootOverride(
      checkoutDir: checkoutDir,
      serverNativePath: p.normalize(packageRoot),
    );
    if (localPrebuiltLibrary != null) {
      await _seedLocalPrebuiltForFramework(
        checkoutDir: checkoutDir,
        library: localPrebuiltLibrary,
      );
    }

    if (options.skipTests) {
      continue;
    }

    for (final mode in options.modes) {
      stdout.writeln('\n=== ${framework.name}: test mode=${mode.name} ===');
      final modeResults = await _runFrameworkSuite(
        framework: framework,
        checkoutDir: checkoutDir,
        mode: mode,
        localPrebuiltPath: localPrebuiltLibrary?.path,
        stopOnFailure: options.failFast,
      );
      results.addAll(modeResults);
      final modeFailed = modeResults.any((r) => r.exitCode != 0);
      if (modeFailed) {
        hasFailures = true;
        if (options.failFast) {
          break;
        }
      }
    }

    if (hasFailures && options.failFast) {
      break;
    }
  }

  _printSummary(results);

  if (options.jsonOutput != null) {
    final outputFile = File(
      p.isAbsolute(options.jsonOutput!)
          ? options.jsonOutput!
          : p.join(repoRoot.path, options.jsonOutput!),
    );
    await outputFile.parent.create(recursive: true);
    final jsonPayload = {
      'workspaceRoot': workspaceRoot.path,
      'frameworks': selectedFrameworks.toList(),
      'modes': options.modes.map((m) => m.name).toList(),
      'results': results.map((r) => r.toJson()).toList(),
      'passed': results.isNotEmpty && results.every((r) => r.exitCode == 0),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonPayload),
    );
    stdout.writeln('Wrote JSON report: ${outputFile.path}');
  }

  if (hasFailures ||
      (results.isNotEmpty && results.any((r) => r.exitCode != 0))) {
    exitCode = 1;
  }
}

File? _findLocalNativeLibrary(String packageRoot) {
  final libraryName = _hostNativeLibraryName();
  final candidates = <String>[
    p.join(packageRoot, 'native', 'target', 'debug', libraryName),
    p.join(packageRoot, 'native', 'target', 'release', libraryName),
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}

Future<void> _seedLocalPrebuiltForFramework({
  required Directory checkoutDir,
  required File library,
}) async {
  final platformLabel = _hostPlatformLabel();
  final libraryName = _hostNativeLibraryName();
  final roots = await _compatCheckoutRoots(checkoutDir);
  for (final root in roots) {
    final destinationRoots = <String>[
      p.join(
        root.path,
        '.dart_tool',
        'server_native',
        'prebuilt',
        serverNativePrebuiltReleaseTag,
        platformLabel,
      ),
      p.join(
        root.path,
        '.dart_tool',
        'server_native',
        'prebuilt',
        platformLabel,
      ),
    ];
    for (final destinationRoot in destinationRoots) {
      final destination = File(p.join(destinationRoot, libraryName));
      await destination.parent.create(recursive: true);
      await library.copy(destination.path);
    }
  }
}

Future<Set<Directory>> _compatCheckoutRoots(Directory checkoutDir) async {
  final roots = <Directory>{checkoutDir};
  final workspacePackages = await _loadWorkspacePackages(checkoutDir);
  for (final package in workspacePackages) {
    final packageDir = Directory(p.join(checkoutDir.path, package));
    if (File(p.join(packageDir.path, 'pubspec.yaml')).existsSync()) {
      roots.add(packageDir);
    }
  }

  final pkgsDir = Directory(p.join(checkoutDir.path, 'pkgs'));
  if (pkgsDir.existsSync()) {
    await for (final entity in pkgsDir.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      if (File(p.join(entity.path, 'pubspec.yaml')).existsSync()) {
        roots.add(entity);
      }
    }
  }

  return roots;
}

String _hostNativeLibraryName() {
  if (Platform.isWindows) {
    return 'server_native.dll';
  }
  if (Platform.isMacOS) {
    return 'libserver_native.dylib';
  }
  return 'libserver_native.so';
}

String _hostPlatformLabel() {
  final os = Platform.operatingSystem;
  final arch = switch (Platform.version) {
    final value when value.contains('x64') => 'x64',
    final value when value.contains('arm64') => 'arm64',
    _ => 'x64',
  };
  final normalizedOs = switch (os) {
    'linux' => 'linux',
    'macos' => 'macos',
    'windows' => 'windows',
    _ => os,
  };
  return '$normalizedOs-$arch';
}

Future<void> _writeRootOverride({
  required Directory checkoutDir,
  required String serverNativePath,
}) async {
  final overrides = File(p.join(checkoutDir.path, 'pubspec_overrides.yaml'));
  final normalizedPath = serverNativePath.replaceAll('\\', '/');
  final contents =
      '''
dependency_overrides:
  server_native:
    path: '$normalizedPath'
''';
  await overrides.writeAsString(contents);
}

Future<void> _syncRepo({
  required _FrameworkConfig framework,
  required Directory checkoutDir,
  required bool fresh,
}) async {
  if (fresh && checkoutDir.existsSync()) {
    checkoutDir.deleteSync(recursive: true);
  }

  if (!checkoutDir.existsSync()) {
    await _runChecked(
      'git',
      [
        'clone',
        '--depth=1',
        '--branch',
        framework.branch,
        framework.gitUrl,
        checkoutDir.path,
      ],
      workingDirectory: checkoutDir.parent.path,
      label: '${framework.name}: clone',
    );
    return;
  }

  await _runChecked(
    'git',
    ['fetch', '--depth=1', 'origin', framework.branch],
    workingDirectory: checkoutDir.path,
    label: '${framework.name}: fetch',
  );
  await _runChecked(
    'git',
    ['checkout', '-f', framework.branch],
    workingDirectory: checkoutDir.path,
    label: '${framework.name}: checkout',
  );
  await _runChecked(
    'git',
    ['reset', '--hard', 'origin/${framework.branch}'],
    workingDirectory: checkoutDir.path,
    label: '${framework.name}: reset',
  );
  await _runChecked(
    'git',
    ['clean', '-fdx'],
    workingDirectory: checkoutDir.path,
    label: '${framework.name}: clean',
  );
}

Future<void> _applyPatch({
  required _FrameworkConfig framework,
  required Directory checkoutDir,
  required File patchFile,
  required String serverNativePath,
}) async {
  if (!patchFile.existsSync()) {
    throw StateError('Missing patch file: ${patchFile.path}');
  }

  final rawPatch = await patchFile.readAsString();
  final normalizedPath = serverNativePath.replaceAll('\\\\', '/');
  final patchBody = rawPatch.replaceAll(
    '__SERVER_NATIVE_PATH__',
    normalizedPath,
  );

  final tempPatch = File(
    p.join(
      Directory.systemTemp.path,
      'server_native_${framework.name}_${DateTime.now().microsecondsSinceEpoch}.patch',
    ),
  );
  await tempPatch.writeAsString(patchBody);

  try {
    final canApply = await _run(
      'git',
      ['apply', '--check', tempPatch.path],
      workingDirectory: checkoutDir.path,
      label: '${framework.name}: patch-check',
    );
    if (canApply.exitCode == 0) {
      await _runChecked(
        'git',
        ['apply', tempPatch.path],
        workingDirectory: checkoutDir.path,
        label: '${framework.name}: patch-apply',
      );
      return;
    }

    final alreadyApplied = await _run(
      'git',
      ['apply', '-R', '--check', tempPatch.path],
      workingDirectory: checkoutDir.path,
      label: '${framework.name}: patch-reverse-check',
    );

    if (alreadyApplied.exitCode == 0) {
      stdout.writeln('${framework.name}: patch already applied');
      return;
    }

    throw StateError(
      'Failed to apply patch ${patchFile.path} for ${framework.name}',
    );
  } finally {
    if (tempPatch.existsSync()) {
      tempPatch.deleteSync();
    }
  }
}

Future<List<_CommandResult>> _runFrameworkSuite({
  required _FrameworkConfig framework,
  required Directory checkoutDir,
  required _CompatMode mode,
  required String? localPrebuiltPath,
  required bool stopOnFailure,
}) async {
  switch (framework.name) {
    case 'shelf':
      return _runShelfSuite(
        checkoutDir,
        mode,
        localPrebuiltPath: localPrebuiltPath,
        stopOnFailure: stopOnFailure,
      );
    case 'relic':
      return _runWorkspaceSuite(
        checkoutDir,
        mode,
        framework: framework.name,
        localPrebuiltPath: localPrebuiltPath,
        stopOnFailure: stopOnFailure,
      );
    case 'serinus':
      return _runWorkspaceSuite(
        checkoutDir,
        mode,
        framework: framework.name,
        localPrebuiltPath: localPrebuiltPath,
        stopOnFailure: stopOnFailure,
      );
    default:
      throw StateError('Unsupported framework: ${framework.name}');
  }
}

Future<List<_CommandResult>> _runShelfSuite(
  Directory checkoutDir,
  _CompatMode mode, {
  required String? localPrebuiltPath,
  required bool stopOnFailure,
}) async {
  final env = _compatEnvironment(
    mode: mode,
    localPrebuiltPath: localPrebuiltPath,
  );

  final packageDirs = <String>[
    'pkgs/shelf',
    'pkgs/shelf_proxy',
    'pkgs/shelf_router',
    'pkgs/shelf_web_socket',
  ];

  final results = <_CommandResult>[];

  for (final packageDir in packageDirs) {
    results.add(
      await _run(
        'dart',
        ['pub', 'get'],
        workingDirectory: p.join(checkoutDir.path, packageDir),
        environment: env,
        framework: 'shelf',
        mode: mode.name,
        commandName: '$packageDir: pub get',
      ),
    );
    if (stopOnFailure && results.last.exitCode != 0) {
      return results;
    }
  }

  for (final packageDir in packageDirs) {
    results.add(
      await _run(
        'dart',
        ['test'],
        workingDirectory: p.join(checkoutDir.path, packageDir),
        environment: env,
        framework: 'shelf',
        mode: mode.name,
        commandName: '$packageDir: dart test',
      ),
    );
    if (stopOnFailure && results.last.exitCode != 0) {
      return results;
    }
  }

  return results;
}

Future<List<_CommandResult>> _runWorkspaceSuite(
  Directory checkoutDir,
  _CompatMode mode, {
  required String framework,
  required String? localPrebuiltPath,
  required bool stopOnFailure,
}) async {
  final env = _compatEnvironment(
    mode: mode,
    localPrebuiltPath: localPrebuiltPath,
  );

  final results = <_CommandResult>[];

  results.add(
    await _run(
      'dart',
      ['pub', 'get'],
      workingDirectory: checkoutDir.path,
      environment: env,
      framework: framework,
      mode: mode.name,
      commandName: 'root: dart pub get',
    ),
  );
  if (stopOnFailure && results.last.exitCode != 0) {
    return results;
  }

  final workspacePackages = await _loadWorkspacePackages(checkoutDir);
  for (final package in workspacePackages) {
    final packageDir = Directory(p.join(checkoutDir.path, package));
    final testDir = Directory(p.join(packageDir.path, 'test'));
    if (!testDir.existsSync()) {
      continue;
    }

    results.add(
      await _run(
        'dart',
        ['test'],
        workingDirectory: packageDir.path,
        environment: env,
        framework: framework,
        mode: mode.name,
        commandName: '$package: dart test',
      ),
    );

    if (stopOnFailure && results.last.exitCode != 0) {
      return results;
    }
  }

  return results;
}

Map<String, String> _compatEnvironment({
  required _CompatMode mode,
  required String? localPrebuiltPath,
}) {
  final env = <String, String>{
    ...Platform.environment,
    'SERVER_NATIVE_COMPAT': mode == _CompatMode.native ? 'true' : 'false',
  };
  if (mode == _CompatMode.native && localPrebuiltPath != null) {
    env['SERVER_NATIVE_PREBUILT'] = localPrebuiltPath;
  } else {
    env.remove('SERVER_NATIVE_PREBUILT');
  }
  return env;
}

Future<List<String>> _loadWorkspacePackages(Directory repoDir) async {
  final pubspec = File(p.join(repoDir.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    return <String>[];
  }

  final lines = await pubspec.readAsLines();
  final packages = <String>[];
  var inWorkspace = false;

  for (final line in lines) {
    if (!inWorkspace) {
      if (line.trim() == 'workspace:') {
        inWorkspace = true;
      }
      continue;
    }

    if (line.trim().isEmpty) {
      continue;
    }

    final startsTopLevel = !line.startsWith(' ') && !line.startsWith('\t');
    if (startsTopLevel) {
      break;
    }

    final match = RegExp(r'^\s*-\s*([^\s#]+)').firstMatch(line);
    if (match != null) {
      packages.add(match.group(1)!);
    }
  }

  return packages;
}

void _printSummary(List<_CommandResult> results) {
  if (results.isEmpty) {
    stdout.writeln('\nNo commands executed.');
    return;
  }

  stdout.writeln('\n=== Summary ===');

  final grouped = <String, List<_CommandResult>>{};
  for (final result in results) {
    final key = '${result.framework}:${result.mode}';
    grouped.putIfAbsent(key, () => <_CommandResult>[]).add(result);
  }

  for (final key in grouped.keys) {
    final commands = grouped[key]!;
    final failed = commands.where((c) => c.exitCode != 0).length;
    final durationMs = commands.fold<int>(0, (sum, c) => sum + c.durationMs);
    final status = failed == 0 ? 'PASS' : 'FAIL';
    stdout.writeln(
      '$status $key (${commands.length} commands, ${durationMs}ms, failed=$failed)',
    );
  }

  final failedTotal = results.where((r) => r.exitCode != 0).length;
  stdout.writeln(
    failedTotal == 0
        ? 'All compatibility commands passed.'
        : 'Compatibility failures: $failedTotal command(s).',
  );
}

Future<_CommandResult> _run(
  String executable,
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
  String? framework,
  String? mode,
  String? commandName,
  String? label,
}) async {
  final commandString = '$executable ${args.join(' ')}';
  final prefix = label ?? commandName ?? commandString;
  stdout.writeln('\n[[36m$prefix[0m] cwd=$workingDirectory');

  final started = DateTime.now();
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: true,
  );

  final stdoutDone = stdout.addStream(process.stdout);
  final stderrDone = stderr.addStream(process.stderr);
  final exitCode = await process.exitCode;
  await stdoutDone;
  await stderrDone;

  final durationMs = DateTime.now().difference(started).inMilliseconds;

  final result = _CommandResult(
    framework: framework ?? 'internal',
    mode: mode ?? 'n/a',
    commandName: commandName ?? commandString,
    command: commandString,
    workingDirectory: workingDirectory,
    exitCode: exitCode,
    durationMs: durationMs,
  );

  final status = exitCode == 0 ? 'ok' : 'exit=$exitCode';
  stdout.writeln('[[36m$prefix[0m] $status (${durationMs}ms)');

  return result;
}

Future<void> _runChecked(
  String executable,
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
  required String label,
}) async {
  final result = await _run(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    label: label,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      'Command failed (${result.exitCode})',
      result.exitCode,
    );
  }
}

Directory _findRepoRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final marker = File(
      p.join(current.path, 'packages', 'server_native', 'pubspec.yaml'),
    );
    if (marker.existsSync()) {
      return current;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate repository root containing packages/server_native/pubspec.yaml',
      );
    }
    current = parent;
  }
}

void _printUsage() {
  stdout.writeln('''
server_native framework compatibility runner

Usage:
  dart run packages/server_native/tool/framework_compat.dart [options]

Options:
  --workspace-root=<path>   Checkout workspace root.
                            Default: .dart_tool/server_native/framework_compat
  --framework=<list>        Comma-separated: all,shelf,relic,serinus
                            Default: all
  --mode=<list>             Comma-separated: both,io,native
                            Default: both
  --fresh                   Delete existing checkouts before clone.
  --skip-tests              Only sync repositories and apply patches.
  --fail-fast               Stop at first failing command.
  --json-output=<path>      Write JSON summary report.
  -h, --help                Show this help.

Env passed to tests:
  SERVER_NATIVE_COMPAT=true|false
''');
}

class _FrameworkConfig {
  final String name;
  final String gitUrl;
  final String branch;
  final String patchFile;

  const _FrameworkConfig({
    required this.name,
    required this.gitUrl,
    required this.branch,
    required this.patchFile,
  });
}

enum _CompatMode { io, native }

extension on _CompatMode {
  String get name => this == _CompatMode.io ? 'io' : 'native';
}

class _CliOptions {
  final String workspaceRoot;
  final Set<String> frameworks;
  final List<_CompatMode> modes;
  final bool fresh;
  final bool skipTests;
  final bool failFast;
  final String? jsonOutput;
  final bool showHelp;

  const _CliOptions({
    required this.workspaceRoot,
    required this.frameworks,
    required this.modes,
    required this.fresh,
    required this.skipTests,
    required this.failFast,
    required this.jsonOutput,
    required this.showHelp,
  });

  static _CliOptions parse(List<String> args) {
    var workspaceRoot = '.dart_tool/server_native/framework_compat';
    var frameworks = <String>{'all'};
    var modeArg = 'both';
    var fresh = false;
    var skipTests = false;
    var failFast = false;
    String? jsonOutput;
    var showHelp = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        showHelp = true;
      } else if (arg == '--fresh') {
        fresh = true;
      } else if (arg == '--skip-tests') {
        skipTests = true;
      } else if (arg == '--fail-fast') {
        failFast = true;
      } else if (arg.startsWith('--workspace-root=')) {
        workspaceRoot = arg.substring('--workspace-root='.length).trim();
      } else if (arg.startsWith('--framework=')) {
        frameworks = arg
            .substring('--framework='.length)
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
      } else if (arg.startsWith('--mode=')) {
        modeArg = arg.substring('--mode='.length).trim();
      } else if (arg.startsWith('--json-output=')) {
        jsonOutput = arg.substring('--json-output='.length).trim();
      } else {
        throw ArgumentError('Unknown argument: $arg');
      }
    }

    if (frameworks.isEmpty) {
      frameworks = {'all'};
    }

    final modes = <_CompatMode>[];
    for (final token in modeArg.split(',').map((e) => e.trim())) {
      if (token.isEmpty) {
        continue;
      }
      switch (token) {
        case 'both':
          modes
            ..clear()
            ..addAll([_CompatMode.io, _CompatMode.native]);
          break;
        case 'io':
          modes.add(_CompatMode.io);
          break;
        case 'native':
          modes.add(_CompatMode.native);
          break;
        default:
          throw ArgumentError('Unknown mode: $token');
      }
    }

    if (modes.isEmpty) {
      modes.addAll([_CompatMode.io, _CompatMode.native]);
    }

    return _CliOptions(
      workspaceRoot: workspaceRoot,
      frameworks: frameworks,
      modes: modes,
      fresh: fresh,
      skipTests: skipTests,
      failFast: failFast,
      jsonOutput: jsonOutput,
      showHelp: showHelp,
    );
  }
}

class _CommandResult {
  final String framework;
  final String mode;
  final String commandName;
  final String command;
  final String workingDirectory;
  final int exitCode;
  final int durationMs;

  const _CommandResult({
    required this.framework,
    required this.mode,
    required this.commandName,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.durationMs,
  });

  Map<String, Object> toJson() => {
    'framework': framework,
    'mode': mode,
    'commandName': commandName,
    'command': command,
    'workingDirectory': workingDirectory,
    'exitCode': exitCode,
    'durationMs': durationMs,
  };
}
