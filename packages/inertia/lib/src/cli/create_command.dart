library;

import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:artisanal/artisanal.dart';
import 'package:path/path.dart' as p;

import 'cli_utils.dart';
import 'framework.dart';
import 'inertia_cli.dart';
import 'package_manager.dart';

/// Implements the `inertia create` command.
///
/// ```dart
/// final exitCode = await InertiaCreateCommand(cli).run();
/// ```
///
/// Scaffolds a Vite project and configures Inertia client files.
class InertiaCreateCommand extends Command<int> {
  /// Creates the `create` command bound to [InertiaCli].
  InertiaCreateCommand(this._cli) {
    argParser
      ..addOption(
        'framework',
        abbr: 'f',
        defaultsTo: 'react',
        allowed: const ['react', 'vue', 'svelte'],
        help: 'Framework adapter to scaffold (react, vue, svelte).',
      )
      ..addOption(
        'package-manager',
        abbr: 'p',
        defaultsTo: 'npm',
        allowed: const ['npm', 'pnpm', 'yarn', 'bun'],
        help: 'Package manager to use for setup.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Directory for the new project (defaults to the name).',
      )
      ..addFlag(
        'force',
        abbr: 'F',
        help: 'Allow creating into a non-empty directory.',
      );
  }

  final InertiaCli _cli;

  @override
  /// The command name.
  String get name => 'create';

  @override
  /// The command description.
  String get description =>
      'Scaffold a Vite project with Inertia client setup.';

  @override
  /// The command invocation string.
  String get invocation => 'inertia create <name> [options]';

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
    final outputOverride = argResults?['output'] as String?;
    final force = argResults?['force'] == true;
    final name = _resolveName(argResults);
    if (name == null) {
      usageException('Provide a project name.');
    }

    final output = outputOverride ?? name;
    final projectDir = Directory(
      p.normalize(p.join(_cli.workingDirectory.path, output)),
    );

    if (await projectDir.exists()) {
      final entries = await projectDir.list().toList();
      if (entries.isNotEmpty && !force) {
        usageException(
          'Directory ${projectDir.path} is not empty. Use --force to continue.',
        );
      }
    }

    io.title('Creating Inertia ${framework.label} app');

    final created = await io.task(
      'Scaffolding Vite project',
      run: () => runInertiaCommand(
        manager.createCommand,
        manager.createArgs(framework.viteTemplate, output),
        workingDirectory: _cli.workingDirectory,
      ),
    );
    if (created == TaskResult.failure) return 1;

    final install = await io.task(
      'Installing dependencies',
      run: () => runInertiaCommand(
        manager.command,
        manager.installArgs,
        workingDirectory: projectDir,
      ),
    );
    if (install == TaskResult.failure) return 1;

    final adapterDeps = framework.dependencies;
    final added = await io.task(
      'Adding Inertia adapter',
      run: () => runInertiaCommand(
        manager.command,
        manager.addArgs(adapterDeps),
        workingDirectory: projectDir,
      ),
    );
    if (added == TaskResult.failure) return 1;

    await io.task(
      'Configuring project files',
      run: () async {
        await configureInertiaProject(projectDir, framework);
        return TaskResult.success;
      },
    );

    io.success('Inertia client created at ${projectDir.path}');
    io.newLine();
    io.writeln('Next steps:');
    io.writeln('  cd ${p.relative(projectDir.path)}');
    io.writeln('  ${manager.command} run dev');
    return 0;
  }

  /// Resolves the project name from [results], if provided.
  String? _resolveName(ArgResults? results) {
    final rest = results?.rest ?? const [];
    if (rest.isNotEmpty) return rest.first;
    return null;
  }
}
