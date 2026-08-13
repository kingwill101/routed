import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed_cli/src/console/args/base_command.dart';
import 'package:routed_cli/src/console/util/dart_exec.dart';
import 'package:routed_cli/src/console/util/pubspec.dart';

/// Builds and deploys a Routed application without user-authored shell files.
class DeployCommand extends BaseCommand {
  DeployCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'target',
        help: 'Deployment target.',
        allowed: const ['cloudflare', 'netlify'],
        defaultsTo: 'cloudflare',
      )
      ..addOption(
        'entry',
        help: 'Dart library that exports createEngine().',
        valueHelp: 'package:my_app/app.dart',
      )
      ..addOption(
        'name',
        help: 'Cloudflare Worker name (defaults to the package name).',
        valueHelp: 'worker-name',
      )
      ..addOption(
        'compatibility-date',
        help: 'Cloudflare compatibility date (defaults to today).',
      )
      ..addFlag(
        'dry-run',
        help: 'Build and validate without uploading.',
        defaultsTo: false,
        negatable: false,
      )
      ..addFlag(
        'keep-vars',
        help: 'Keep variables configured in the Cloudflare dashboard.',
        defaultsTo: false,
        negatable: false,
      );
  }

  @override
  String get name => 'deploy';

  @override
  String get description => 'Build and deploy a Routed application.';

  @override
  String get category => 'Deployment';

  @override
  Future<void> run() => guarded(() async {
    final root = await findProjectRoot();
    if (root == null) {
      throw UsageException('Could not locate a pubspec.yaml.', usage);
    }

    final target = results?['target'] as String? ?? 'cloudflare';
    if (target != 'cloudflare' && target != 'netlify') {
      throw UsageException('Unsupported deployment target: $target', usage);
    }

    final packageName = await readPackageName(root);
    if (packageName == null) {
      throw UsageException(
        'pubspec.yaml does not contain a package name.',
        usage,
      );
    }

    await _ensureRoutedNode(root);
    if (target == 'netlify') {
      await _deployNetlify(root, packageName);
      return;
    }

    final requestedName = (results?['name'] as String?)?.trim();
    final workerName = _sanitizeWorkerName(
      requestedName == null || requestedName.isEmpty
          ? packageName
          : requestedName,
    );
    final date =
        results?['compatibility-date'] as String? ??
        DateTime.now().toIso8601String().substring(0, 10);
    final dryRun = results?['dry-run'] as bool? ?? false;
    final keepVars = results?['keep-vars'] as bool? ?? false;
    final entry = _resolveImport(packageName, results?['entry'] as String?);

    final buildRoot = root.fileSystem.directory(
      p.join(root.path, '.dart_tool', 'routed', 'deploy', target),
    );
    await buildRoot.create(recursive: true);

    final dartEntry = root.fileSystem.file(
      p.join(buildRoot.path, 'worker_entry.dart'),
    );
    final jsOutput = root.fileSystem.file(
      p.join(buildRoot.path, 'worker.dart.js'),
    );
    final workerOutput = root.fileSystem.file(
      p.join(buildRoot.path, 'worker.js'),
    );
    final configOutput = root.fileSystem.file(
      p.join(buildRoot.path, 'wrangler.jsonc'),
    );

    await dartEntry.writeAsString(
      _workerEntrySource(packageName: packageName, importPath: entry),
    );
    await _runDart(root, [
      'compile',
      'js',
      dartEntry.path,
      '-o',
      jsOutput.path,
      '-O2',
    ], label: 'Compiling Cloudflare Worker');
    await workerOutput.writeAsString(_workerWrapper(jsOutput.path));

    final config = <String, Object?>{
      r'$schema':
          'https://developers.cloudflare.com/workers/wrangler/config-schema.json',
      'name': workerName,
      'main': p.basename(workerOutput.path),
      'compatibility_date': date,
      'compatibility_flags': ['nodejs_compat'],
    };
    await configOutput.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    final wranglerArgs = <String>['wrangler@latest', 'deploy'];
    if (dryRun) wranglerArgs.add('--dry-run');
    if (keepVars) wranglerArgs.add('--keep-vars');
    wranglerArgs.add('--config');
    wranglerArgs.add(configOutput.path);
    await _runNpx(root, wranglerArgs, label: 'Deploying Cloudflare Worker');

    logger.info('Routed Cloudflare deployment complete: $workerName');
  });

  Future<void> _deployNetlify(fs.Directory root, String packageName) async {
    final requestedName = (results?['name'] as String?)?.trim();
    final siteName = requestedName == null || requestedName.isEmpty
        ? _sanitizeWorkerName(packageName)
        : _sanitizeWorkerName(requestedName);
    final dryRun = results?['dry-run'] as bool? ?? false;
    final buildRoot = root.fileSystem.directory(
      p.join(root.path, '.dart_tool', 'routed', 'deploy', 'netlify'),
    );
    final edgeRoot = root.fileSystem.directory(
      p.join(buildRoot.path, 'netlify', 'edge-functions'),
    );
    await edgeRoot.create(recursive: true);
    final dartEntry = root.fileSystem.file(
      p.join(buildRoot.path, 'worker_entry.dart'),
    );
    final jsOutput = root.fileSystem.file(
      p.join(buildRoot.path, 'worker.dart.js'),
    );
    await dartEntry.writeAsString(_netlifyWorkerEntry(packageName));
    await _runDart(root, [
      'compile',
      'js',
      dartEntry.path,
      '-o',
      jsOutput.path,
      '-O2',
    ], label: 'Compiling Netlify Edge Function');
    final handler = root.fileSystem.file(p.join(edgeRoot.path, 'routed.js'));
    await handler.writeAsString(_netlifyHandler());
    final config = root.fileSystem.file(p.join(buildRoot.path, 'netlify.toml'));
    await config.writeAsString('''
[build]
  edge_functions = "netlify/edge-functions"
''');

    if (dryRun) {
      logger.info('Netlify build validation complete: $siteName');
      return;
    }

    final args = <String>[
      'netlify-cli@latest',
      'deploy',
      '--no-build',
      '--dir',
      '.',
      '--site',
      siteName,
      '--prod',
    ];
    await _runNpx(buildRoot, args, label: 'Deploying Netlify Edge Function');
    logger.info('Routed Netlify deployment complete: $siteName');
  }

  String _netlifyWorkerEntry(String packageName) =>
      '''
import 'package:routed_node/netlify.dart';
import 'package:$packageName/app.dart' as app;

void main() {
  defineNetlifyFetchAsync(app.createEngine());
}
''';

  String _netlifyHandler() => '''
import "../../worker.dart.js";

export default async (request, context) => {
  return await globalThis.__routed_fetch__(request, context, {});
};

export const config = { path: "/*" };
''';

  Future<void> _ensureRoutedNode(fs.Directory root) async {
    final pubspec = root.fileSystem.file(p.join(root.path, 'pubspec.yaml'));
    final contents = await pubspec.readAsString();
    final dependencyPattern = RegExp(r'^\s+routed_node\s*:', multiLine: true);
    if (dependencyPattern.hasMatch(contents)) return;

    logger.info('Adding deployment adapter: routed_node …');
    final code = await _runDart(root, [
      'pub',
      'add',
      'routed_node',
    ], label: 'Resolving deployment dependencies');
    if (code != 0) {
      throw StateError('Unable to add routed_node to the application.');
    }
  }

  Future<int> _runDart(
    fs.Directory root,
    List<String> arguments, {
    required String label,
  }) async {
    logger.info('$label …');
    final process = await io.Process.start(
      resolveDartExecutable(),
      arguments,
      workingDirectory: root.path,
      mode: io.ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) throw StateError('$label failed with exit code $code.');
    return code;
  }

  Future<void> _runNpx(
    fs.Directory root,
    List<String> arguments, {
    required String label,
  }) async {
    logger.info('$label …');
    final process = await io.Process.start(
      'npx',
      ['--yes', ...arguments],
      workingDirectory: root.path,
      mode: io.ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      throw StateError(
        '$label failed with exit code $code. Check the target CLI '
        'authentication and site configuration.',
      );
    }
  }

  String _resolveImport(String packageName, String? requested) {
    final value = requested?.trim();
    if (value == null || value.isEmpty) return 'package:$packageName/app.dart';
    if (value.startsWith('package:')) return value;
    if (value.startsWith('lib/')) {
      return 'package:$packageName/${value.substring('lib/'.length)}';
    }
    return value;
  }

  String _workerEntrySource({
    required String packageName,
    required String importPath,
  }) =>
      '''
import 'package:routed_node/cloudflare.dart';
import '$importPath' as app;

void main() {
  defineCloudflareFetchAsync(app.createEngine());
}
''';

  String _workerWrapper(String compiledPath) {
    final relative = p.basename(compiledPath);
    return '''import './$relative';

export default {
  async fetch(request, env, ctx) {
    return await globalThis.__routed_fetch__(request, ctx, env);
  },
};
''';
  }

  String _sanitizeWorkerName(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
        .replaceFirst(RegExp(r'^-+'), '')
        .replaceFirst(RegExp(r'-+$'), '');
    return normalized.isEmpty ? 'routed-worker' : normalized;
  }
}
