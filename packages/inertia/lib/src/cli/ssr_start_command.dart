library;

import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:artisanal/artisanal.dart';
import 'package:path/path.dart' as p;

import '../ssr/ssr_server.dart';
import '../ssr/ssr_server_config.dart';
import 'inertia_cli.dart';
import 'ssr_utils.dart';

/// Implements the `inertia ssr:start` command.
///
/// ```dart
/// final exitCode = await InertiaSsrStartCommand(cli).run();
/// ```
///
/// Starts the SSR server process.
class InertiaSsrStartCommand extends Command<int> {
  /// Creates the `ssr:start` command bound to [InertiaCli].
  InertiaSsrStartCommand(this._cli) {
    argParser
      ..addOption(
        'runtime',
        abbr: 'r',
        defaultsTo: 'node',
        allowed: const ['node', 'bun'],
        help: 'Runtime for the SSR bundle (node or bun).',
      )
      ..addOption(
        'bundle',
        abbr: 'b',
        help: 'Path to the SSR bundle (default: auto-detect).',
      )
      ..addMultiOption(
        'bundle-candidate',
        abbr: 'c',
        help: 'Additional SSR bundle paths to check.',
      )
      ..addMultiOption(
        'runtime-arg',
        abbr: 'a',
        help: 'Extra runtime arguments passed to the SSR process.',
      )
      ..addMultiOption(
        'env',
        abbr: 'e',
        help: 'Environment variables for the SSR process (KEY=VALUE).',
      )
      ..addOption(
        'working-directory',
        abbr: 'w',
        help: 'Directory to resolve bundle paths from.',
      );
  }

  final InertiaCli _cli;

  @override
  /// The command name.
  String get name => 'ssr:start';

  @override
  /// The command description.
  String get description => 'Start the Inertia SSR server bundle.';

  @override
  /// Runs the command and returns an exit code.
  Future<int> run() async {
    final io = this.io;
    final runtime = argResults?['runtime'] as String? ?? 'node';
    final bundleOption = argResults?['bundle'] as String?;
    final bundleCandidates =
        (argResults?['bundle-candidate'] as List<String>? ?? const [])
            .where((value) => value.trim().isNotEmpty)
            .toList();
    final runtimeArgs =
        (argResults?['runtime-arg'] as List<String>? ?? const [])
            .where((value) => value.trim().isNotEmpty)
            .toList();
    final environment = parseEnvironment(
      argResults?['env'] as List<String>? ?? const [],
    );
    final workingDirOption = argResults?['working-directory'] as String?;
    final workingDirectory = workingDirOption == null
        ? _cli.workingDirectory
        : Directory(p.normalize(workingDirOption));

    final config = SsrServerConfig(
      runtime: runtime,
      bundle: bundleOption,
      runtimeArgs: runtimeArgs,
      bundleCandidates: bundleCandidates,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final bundle = config.resolveBundle();
    if (bundle == null) {
      io.error('Inertia SSR bundle not found.');
      io.note('Provide --bundle or place it in bootstrap/ssr/ssr.mjs.');
      return 1;
    }

    if (bundleOption != null &&
        p.normalize(bundle) != p.normalize(bundleOption)) {
      io.note('Configured bundle not found at $bundleOption.');
      io.note('Using detected bundle: $bundle');
    }

    if (runtime != 'node' && runtime != 'bun') {
      io.error('Unsupported runtime: $runtime. Use node or bun.');
      return 64;
    }

    io.title('Starting Inertia SSR');
    io.twoColumnDetail('Runtime', runtime);
    io.twoColumnDetail('Bundle', bundle);

    final process = await startSsrServer(config, inheritStdio: false);
    attachSignals(process, io);

    return pipeSsrProcess(
      process,
      stdoutSink: _cli.stdoutSink,
      stderrSink: _cli.stderrSink,
    );
  }
}
