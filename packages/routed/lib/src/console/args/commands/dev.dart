import 'dart:async';
import 'dart:io' as io;

import 'package:routed/console.dart' show CliLogger;
import 'package:routed/src/console/args/base_command.dart';
import 'package:routed/src/console/dev/dev_server_runner.dart' as dev;
import 'package:routed/src/console/util/dart_exec.dart';

typedef DevServerFactory =
    DevServer Function({
      required CliLogger logger,
      required String port,
      required io.InternetAddress? address,
      required String dartVmServicePort,
      required io.Directory workingDirectory,
      required String scriptPath,
      required bool hotReloadExpected,
      List<String>? additionalWatchPaths,
    });

abstract class DevServer {
  Future<void> start(List<String> arguments);

  Future<dev.ExitCode> get exitCode;
}

class _DefaultDevServer implements DevServer {
  _DefaultDevServer({
    required CliLogger logger,
    required String port,
    required io.InternetAddress? address,
    required String dartVmServicePort,
    required io.Directory workingDirectory,
    required String scriptPath,
    required bool hotReloadExpected,
    List<String>? additionalWatchPaths,
  }) : _runner = dev.DevServerRunner(
         logger: logger,
         port: port,
         address: address,
         dartVmServicePort: dartVmServicePort,
         workingDirectory: workingDirectory,
         scriptPath: scriptPath,
         hotReloadExpected: hotReloadExpected,
         additionalWatchPaths: additionalWatchPaths,
       );

  final dev.DevServerRunner _runner;

  @override
  Future<void> start(List<String> arguments) => _runner.start(arguments);

  @override
  Future<dev.ExitCode> get exitCode => _runner.exitCode;
}

/// Run a local development server with optional hot reload bootstrap.
///
/// Features:
/// - Launches the target entrypoint with `--enable-vm-service` (required for hot reload).
/// - Optionally generates a small bootstrap that initializes `hotreloader` and then
///   calls your entrypoint's `main(List<String> args)`.
/// - Can auto-install `hotreloader` as a dev dependency when missing.
///
/// Options:
/// - --host/-H: Host to bind (default: 127.0.0.1)
/// - --port/-p: Port to bind (default: 8080)
/// - --entry/-e: Entrypoint file to run (default: bin/server.dart)
/// - --watch: Extra files/dirs to watch (reserved for future enhancements)
/// - --bootstrap: Generate and run the hotreloader bootstrap (default: true)
/// - --bootstrap-path: Custom bootstrap file path
/// - --install-missing: Auto-install hotreloader when missing (default: true)
/// - --no-warn-missing: Suppress warning if hotreloader is missing (default: false)
class DevCommand extends BaseCommand {
  DevCommand({super.logger, super.fileSystem, DevServerFactory? runnerFactory})
    : _runnerFactory = runnerFactory ?? _defaultRunnerFactory {
    argParser
      ..addOption(
        'host',
        abbr: 'H',
        help: 'The host to bind.',
        valueHelp: 'host',
        defaultsTo: '127.0.0.1',
      )
      ..addOption(
        'port',
        abbr: 'p',
        help: 'The port to bind.',
        valueHelp: 'port',
        defaultsTo: '8080',
      )
      ..addOption(
        'entry',
        abbr: 'e',
        help: 'Entrypoint file to run in development.',
        valueHelp: 'path',
        defaultsTo: 'bin/server.dart',
      )
      ..addMultiOption(
        'watch',
        help:
            'Additional directories or files to watch for changes (reserved).',
        valueHelp: 'path',
      )
      ..addFlag(
        'bootstrap',
        help:
            'Generate and run a hotreloader bootstrap around your entrypoint.',
        negatable: true,
        defaultsTo: true,
      )
      ..addOption(
        'bootstrap-path',
        help: 'Custom path for the generated bootstrap file.',
        valueHelp: 'path',
      )
      ..addFlag(
        'install-missing',
        help: 'Auto-install dev dependency `hotreloader` if missing.',
        negatable: true,
        defaultsTo: true,
      )
      ..addFlag(
        'no-warn-missing',
        help:
            'Suppress warning when `hotreloader` is missing and auto-install is disabled.',
        negatable: true,
        defaultsTo: false,
      );
  }

  @override
  String get name => 'dev';

  @override
  String get description => 'Run a local development server.';

  @override
  String get category => 'Development';

  final DevServerFactory _runnerFactory;

  static DevServer _defaultRunnerFactory({
    required CliLogger logger,
    required String port,
    required io.InternetAddress? address,
    required String dartVmServicePort,
    required io.Directory workingDirectory,
    required String scriptPath,
    required bool hotReloadExpected,
    List<String>? additionalWatchPaths,
  }) {
    return _DefaultDevServer(
      logger: logger,
      port: port,
      address: address,
      dartVmServicePort: dartVmServicePort,
      workingDirectory: workingDirectory,
      scriptPath: scriptPath,
      hotReloadExpected: hotReloadExpected,
      additionalWatchPaths: additionalWatchPaths,
    );
  }

  @override
  Future<void> run() async {
    return guarded(() async {
      final host = results?['host'] as String? ?? '127.0.0.1';
      final port = int.tryParse(results?['port'] as String? ?? '') ?? 8080;
      final entry = results?['entry'] as String? ?? 'bin/server.dart';
      final watch = (results?['watch'] as List<String>? ?? const <String>[]);
      final useBootstrap = results?['bootstrap'] as bool? ?? true;
      final bootstrapOverride = results?['bootstrap-path'] as String?;
      final installMissing = results?['install-missing'] as bool? ?? true;
      final suppressWarnMissing = results?['no-warn-missing'] as bool? ?? false;

      // Validate entry
      final entryFile = fileSystem.file(entry);
      if (!await entryFile.exists()) {
        logger.error('Entry file not found: $entry');
        io.exitCode = 2;
        return;
      }

      // Try to find project root (directory containing pubspec.yaml)
      final projectRoot = await findProjectRoot();
      if (verbose) {
        logger.debug('Project root: ${projectRoot?.path ?? '(not found)'}');
      }

      // Ensure hotreloader is available if we're using bootstrap
      bool hasHotReloader = false;
      if (useBootstrap && projectRoot != null) {
        final pubspec = projectRoot.fileSystem.file(
          joinPath([projectRoot.path, 'pubspec.yaml']),
        );
        if (await pubspec.exists()) {
          final content = await pubspec.readAsString();
          hasHotReloader = RegExp(
            r'^\s*(dev_dependencies|dependencies)\s*:[\s\S]*?^\s*hotreloader\s*:',
            multiLine: true,
            caseSensitive: false,
          ).hasMatch(content);

          if (!hasHotReloader && installMissing) {
            logger.info('Adding dev dependency: hotreloader');
            final addProc = await startDartProcess(
              ['pub', 'add', '--dev', 'hotreloader'],
              workingDirectory: projectRoot.path,
              mode: io.ProcessStartMode.inheritStdio,
            );
            final addCode = await addProc.exitCode;
            hasHotReloader = addCode == 0;
            if (!hasHotReloader && !suppressWarnMissing) {
              logger.error(
                'Failed to add hotreloader (exit code $addCode). Proceeding without bootstrap.',
              );
            }
          } else if (!hasHotReloader && !suppressWarnMissing) {
            logger.warn(
              'hotreloader not found. You can enable automatic installation via --install-missing.',
            );
          }
        }
      }

      // Prepare bootstrap if requested
      String scriptToRun = entryFile.absolute.path;
      if (useBootstrap &&
          (projectRoot != null) &&
          (hasHotReloader || installMissing)) {
        final root = projectRoot;
        final toolDir = root.fileSystem.directory(
          joinPath([root.path, '.dart_tool', 'routed']),
        );
        await ensureDir(toolDir);
        final bootstrapPath =
            bootstrapOverride ?? joinPath([toolDir.path, 'dev_bootstrap.dart']);

        final importUri = fileSystem
            .file(entry)
            .absolute
            .uri
            .toString(); // file:///...
        final watched = watch.isEmpty ? '' : " // watch: ${watch.join(', ')}";

        final bootstrapSource =
            '''
// GENERATED BY routed: dev bootstrap$watched
import 'dart:io' as io;
import 'package:hotreloader/hotreloader.dart';
import '$importUri' as app;

Future<void> main(List<String> args) async {
  final reloader = await HotReloader.create(
    debounceInterval: const Duration(milliseconds: 500),
    onAfterReload: (ctx) => io.stdout.writeln('Hot-reload result: \${ctx.result}'),
  );

  // Forward SIGINT/SIGTERM to allow graceful shutdown and cleanup.
  io.ProcessSignal.sigint.watch().listen((_) {
    reloader.stop();
    io.exit(130);
  });
  io.ProcessSignal.sigterm.watch().listen((_) {
    reloader.stop();
    io.exit(143);
  });

  await app.main(args);

  // If the app returns, cleanup.
  reloader.stop();
}
''';

        await writeTextFile(fileSystem.file(bootstrapPath), bootstrapSource);
        scriptToRun = fileSystem.file(bootstrapPath).absolute.path;
        if (verbose) {
          logger.debug('Bootstrap generated at: $scriptToRun');
        }
      }

      logger.info('Starting development server:');
      logger.info('  host       : $host');
      logger.info('  port       : $port');
      logger.info('  entry      : $entry');
      if (useBootstrap) {
        logger.info('  bootstrap  : enabled');
      } else {
        logger.info('  bootstrap  : disabled');
      }
      if (watch.isNotEmpty) {
        logger.info('  watch      : ${watch.join(', ')}');
      }
      logger.info('  verbose    : $verbose');
      logger.info('');

      // Use DevServerRunner to manage the dev server lifecycle.
      final workingDirectory = projectRoot != null
          ? io.Directory(projectRoot.path)
          : io.Directory.current;
      final runner = _runnerFactory(
        logger: logger,
        port: '$port',
        address: io.InternetAddress.tryParse(host),
        dartVmServicePort: '8181',
        workingDirectory: workingDirectory,
        scriptPath: scriptToRun,
        hotReloadExpected: useBootstrap,
        additionalWatchPaths: watch,
      );

      await runner.start(['--host', host, '--port', '$port']);
      final result = await runner.exitCode;
      io.exitCode = result.code;
    });
  }
}
