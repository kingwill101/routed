library;

import 'dart:io';

import 'package:artisanal/artisanal.dart';
import 'package:path/path.dart' as p;

import 'cli_utils.dart';
import 'framework.dart';
import 'inertia_cli.dart';
import 'package_manager.dart';

/// Implements the `inertia install` command.
///
/// ```dart
/// final exitCode = await InertiaInstallCommand(cli).run();
/// ```
///
/// Installs Inertia dependencies into an existing Vite project.
class InertiaInstallCommand extends Command<int> {
  /// Creates the `install` command bound to [InertiaCli].
  InertiaInstallCommand(this._cli) {
    argParser
      ..addOption(
        'framework',
        abbr: 'f',
        defaultsTo: 'react',
        allowed: const ['react', 'vue', 'svelte'],
        help: 'Framework adapter to install (react, vue, svelte).',
      )
      ..addOption(
        'package-manager',
        abbr: 'p',
        defaultsTo: 'npm',
        allowed: const ['npm', 'pnpm', 'yarn', 'bun'],
        help: 'Package manager to use for setup.',
      )
      ..addOption(
        'path',
        abbr: 'd',
        help: 'Target directory (defaults to current directory).',
      );
  }

  final InertiaCli _cli;

  @override
  /// The command name.
  String get name => 'install';

  @override
  /// The command description.
  String get description =>
      'Install Inertia dependencies in an existing Vite project.';

  @override
  /// Runs the command and returns an exit code.
  Future<int> run() async {
    final io = this.io;
    final framework = InertiaFramework.parse(
      argResults?['framework'] as String?,
    );
    final manager = InertiaPackageManager.parse(
      argResults?['package-manager'] as String?,
    );
    final pathArg = argResults?['path'] as String?;
    final projectDir = Directory(
      p.normalize(p.join(_cli.workingDirectory.path, pathArg ?? '.')),
    );

    if (!await projectDir.exists()) {
      usageException('Directory not found: ${projectDir.path}');
    }

    io.title('Installing Inertia ${framework.label} adapter');

    final added = await io.task(
      'Adding dependencies',
      run: () => runInertiaCommand(
        manager.command,
        manager.addArgs(framework.dependencies),
        workingDirectory: projectDir,
      ),
    );
    if (added == TaskResult.failure) return 1;

    await io.task(
      'Updating project files',
      run: () async {
        await configureInertiaProject(projectDir, framework);
        return TaskResult.success;
      },
    );

    io.success('Inertia adapter installed.');
    return 0;
  }
}
