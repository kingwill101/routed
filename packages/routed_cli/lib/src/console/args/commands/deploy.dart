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
        allowed: const ['cloudflare', 'netlify', 'vercel'],
        defaultsTo: 'cloudflare',
      )
      ..addOption(
        'entry',
        help: 'Dart library that exports createEngine().',
        valueHelp: 'package:my_app/app.dart',
      )
      ..addOption(
        'runtime',
        help: 'Vercel runtime.',
        allowed: const ['node', 'edge'],
        defaultsTo: 'node',
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
    if (target != 'cloudflare' && target != 'netlify' && target != 'vercel') {
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
    if (target == 'vercel') {
      await _deployVercel(root, packageName);
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

  Future<void> _deployVercel(fs.Directory root, String packageName) async {
    final requestedName = (results?['name'] as String?)?.trim();
    final projectName = requestedName == null || requestedName.isEmpty
        ? _sanitizeWorkerName(packageName)
        : _sanitizeWorkerName(requestedName);
    final dryRun = results?['dry-run'] as bool? ?? false;
    final runtime = results?['runtime'] as String? ?? 'node';
    final entry = _resolveImport(packageName, results?['entry'] as String?);
    if (runtime == 'edge') {
      await _deployVercelEdge(root, packageName, projectName, entry, dryRun);
      return;
    }
    final outputRoot = root.fileSystem.directory(
      p.join(root.path, '.vercel', 'output'),
    );
    final functionRoot = root.fileSystem.directory(
      p.join(outputRoot.path, 'functions', 'routed.func'),
    );
    final sourceRoot = root.fileSystem.directory(
      p.join(root.path, '.dart_tool', 'routed', 'deploy', 'vercel'),
    );
    await functionRoot.create(recursive: true);
    await sourceRoot.create(recursive: true);

    final dartEntry = root.fileSystem.file(
      p.join(sourceRoot.path, 'node_entry.dart'),
    );
    final jsOutput = root.fileSystem.file(
      p.join(functionRoot.path, 'main.dart.js'),
    );
    await dartEntry.writeAsString(_vercelNodeWorkerEntrySource(entry));
    await _runDart(root, [
      'compile',
      'js',
      dartEntry.path,
      '-o',
      jsOutput.path,
      '-O2',
    ], label: 'Compiling Vercel Node.js Function');

    await root.fileSystem
        .file(p.join(functionRoot.path, 'entry.js'))
        .writeAsString(_vercelNodeFunctionEntry());
    if (!dryRun) {
      await _installVercelNodeDependencies(functionRoot);
      await _bundleVercelNodeEntry(functionRoot);
    }
    await root.fileSystem
        .file(p.join(functionRoot.path, '.vc-config.json'))
        .writeAsString('''{
  "runtime": "nodejs22.x",
  "handler": "entry.js",
  "launcherType": "Nodejs",
  "supportsResponseStreaming": true
}
''');
    await outputRoot.fileSystem
        .file(p.join(outputRoot.path, 'config.json'))
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'version': 3,
            'routes': [
              {'src': '/(.*)', 'dest': 'routed'},
            ],
          }),
        );

    if (dryRun) {
      logger.info('Vercel build validation complete: $projectName');
      return;
    }
    await _runNpx(root, [
      'vercel@latest',
      'deploy',
      '--prebuilt',
      '--yes',
    ], label: 'Deploying Vercel Node.js Function');
    logger.info('Vercel deployment complete: $projectName');
  }

  String _vercelNodeWorkerEntrySource(String importPath) =>
      '''
import 'package:routed_node/vercel.dart';
import '$importPath' as app;

void main() {
  defineVercelNodeHandlerFactory(app.createEngine);
}
''';

  String _vercelNodeFunctionEntry() => '''
require('./main.dart.js');
const { WebSocketServer } = require('ws');

async function experimentalUpgradeWebSocket(handler) {
  const context = globalThis[Symbol.for('@vercel/request-context')]?.get?.();
  if (!context || typeof context.upgradeWebSocket !== 'function') {
    throw new Error('Vercel WebSocket upgrades are unavailable in this runtime.');
  }
  const { req, socket, head } = context.upgradeWebSocket();
  const wss = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 });
  const webSocket = await new Promise((resolve, reject) => {
    const cleanup = () => {
      socket.removeListener('error', onError);
      socket.removeListener('close', onClose);
    };
    const onError = (error) => { cleanup(); reject(error); };
    const onClose = () => { cleanup(); reject(new Error('socket closed before upgrade')); };
    socket.once('error', onError);
    socket.once('close', onClose);
    wss.handleUpgrade(req, socket, head, (value) => {
      cleanup();
      resolve(value);
    });
  });
  await handler(webSocket);
  return new Response(null, { status: 204 });
}

module.exports = async (request, response) => {
  if ((request.headers.upgrade || '').toLowerCase() === 'websocket') {
    return experimentalUpgradeWebSocket((webSocket) =>
      globalThis.__routed_vercel_node_websocket__(request, webSocket),
    );
  }
  return globalThis.__routed_vercel_node_request__(request, response);
};
''';

  Future<void> _deployVercelEdge(
    fs.Directory root,
    String packageName,
    String projectName,
    String entry,
    bool dryRun,
  ) async {
    final outputRoot = root.fileSystem.directory(
      p.join(root.path, '.vercel', 'output'),
    );
    final functionRoot = root.fileSystem.directory(
      p.join(outputRoot.path, 'functions', 'routed-edge.func'),
    );
    final sourceRoot = root.fileSystem.directory(
      p.join(root.path, '.dart_tool', 'routed', 'deploy', 'vercel-edge'),
    );
    await functionRoot.create(recursive: true);
    await sourceRoot.create(recursive: true);
    final dartEntry = root.fileSystem.file(
      p.join(sourceRoot.path, 'edge_entry.dart'),
    );
    final jsOutput = root.fileSystem.file(
      p.join(functionRoot.path, 'main.dart.js'),
    );
    await dartEntry.writeAsString(_vercelEdgeWorkerEntrySource(entry));
    await _runDart(root, [
      'compile',
      'js',
      dartEntry.path,
      '-o',
      jsOutput.path,
      '-O2',
    ], label: 'Compiling Vercel Edge Function');
    await root.fileSystem
        .file(p.join(functionRoot.path, 'entry.js'))
        .writeAsString(_vercelEdgeFunctionEntry());
    await root.fileSystem
        .file(p.join(functionRoot.path, '.vc-config.json'))
        .writeAsString('''{
  "runtime": "edge",
  "entrypoint": "entry.js"
}
''');
    await outputRoot.fileSystem
        .file(p.join(outputRoot.path, 'config.json'))
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'version': 3,
            'routes': [
              {'src': '/(.*)', 'dest': 'routed-edge'},
            ],
          }),
        );
    if (dryRun) {
      logger.info('Vercel Edge build validation complete: $projectName');
      return;
    }
    await _runNpx(root, [
      'vercel@latest',
      'deploy',
      '--prebuilt',
      '--yes',
    ], label: 'Deploying Vercel Edge Function');
    logger.info('Vercel deployment complete: $projectName');
  }

  String _vercelEdgeWorkerEntrySource(String importPath) =>
      '''
import 'package:routed_node/vercel.dart';
import '$importPath' as app;

void main() {
  defineVercelFetchFactoryAsync(app.createEngine);
}
''';

  String _vercelEdgeFunctionEntry() => '''
import './main.dart.js';

export default async (request) => {
  return await globalThis.__routed_fetch__(request);
};
''';

  Future<void> _deployNetlify(fs.Directory root, String packageName) async {
    final requestedName = (results?['name'] as String?)?.trim();
    final siteName = requestedName == null || requestedName.isEmpty
        ? _sanitizeWorkerName(packageName)
        : _sanitizeWorkerName(requestedName);
    final dryRun = results?['dry-run'] as bool? ?? false;
    final stagingIo = await io.Directory.systemTemp.createTemp(
      'routed-netlify-',
    );
    final staging = root.fileSystem.directory(stagingIo.path);

    try {
      final edgeRoot = root.fileSystem.directory(
        p.join(staging.path, 'netlify', 'edge-functions'),
      );
      await edgeRoot.create(recursive: true);
      final sourceRoot = root.fileSystem.directory(
        p.join(root.path, '.dart_tool', 'routed', 'deploy', 'netlify'),
      );
      await sourceRoot.create(recursive: true);
      final dartEntry = root.fileSystem.file(
        p.join(sourceRoot.path, 'worker_entry.dart'),
      );
      final jsOutput = root.fileSystem.file(
        p.join(staging.path, 'worker.dart.js'),
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
      final config = root.fileSystem.file(p.join(staging.path, 'netlify.toml'));
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
      await _runNpx(staging, args, label: 'Deploying Netlify Edge Function');
      logger.info('Routed Netlify deployment complete: $siteName');
    } finally {
      await stagingIo.delete(recursive: true);
    }
  }

  String _netlifyWorkerEntry(String packageName) =>
      '''
import 'package:routed_node/netlify.dart';
import 'package:$packageName/app.dart' as app;

void main() {
  defineNetlifyFetchFactoryAsync(app.createEngine);
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

  Future<void> _bundleVercelNodeEntry(fs.Directory functionRoot) async {
    await _runNpx(functionRoot, [
      'esbuild',
      'entry.js',
      '--bundle',
      '--platform=node',
      '--format=cjs',
      '--external:./main.dart.js',
      '--outfile=entry.bundle.js',
    ], label: 'Bundling Vercel Node.js entrypoint');
    final bundled = functionRoot.fileSystem.file(
      p.join(functionRoot.path, 'entry.bundle.js'),
    );
    bundled.copySync(
      functionRoot.fileSystem.file(p.join(functionRoot.path, 'entry.js')).path,
    );
    bundled.deleteSync();
    final nodeModules = functionRoot.fileSystem.directory(
      p.join(functionRoot.path, 'node_modules'),
    );
    if (nodeModules.existsSync()) nodeModules.deleteSync(recursive: true);
  }

  Future<void> _installVercelNodeDependencies(fs.Directory functionRoot) async {
    logger.info('Installing Vercel Node.js WebSocket dependencies …');
    functionRoot.fileSystem
        .file(p.join(functionRoot.path, 'package.json'))
        .writeAsStringSync('{"private":true}\n');
    final process = await io.Process.start(
      'npm',
      ['install', '--no-package-lock', '--omit=dev', 'ws@8.21.3'],
      workingDirectory: functionRoot.path,
      mode: io.ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      throw StateError(
        'Installing Vercel Node.js dependencies failed with exit code $code.',
      );
    }
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
  defineCloudflareFetchFactoryAsync(app.createEngine);
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
