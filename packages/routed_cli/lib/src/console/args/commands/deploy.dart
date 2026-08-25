import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed_cli/src/console/args/base_command.dart';
import 'package:routed_cli/src/console/util/dart_exec.dart';
import 'package:routed_cli/src/console/util/pubspec.dart';

/// Builds and deploys a Routed application without user-authored shell files.
///
/// Cloudflare Workers is the default target. An application that exports
/// `createEngine` can use the default factory:
///
/// ```text
/// routed deploy --target cloudflare
/// ```
///
/// An environment-aware app can opt into the Cloudflare environment factory
/// and declare its platform resources in the generated Wrangler config:
///
/// ```text
/// routed deploy --target cloudflare \
///   --cloudflare-factory environment \
///   --d1 AUTH_DB=auth-db:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
///   --r2 ASSETS=app-assets \
///   --queue JOBS=app-jobs \
///   --service ANALYTICS=analytics-worker
/// ```
///
/// Durable Objects and containers use repeatable options. The class names
/// must be exported by the application entrypoint:
///
/// ```text
/// routed deploy --target cloudflare \
///   --durable-object COUNTER=Counter \
///   --container API=ApiContainer|ghcr.io/example/api:latest|8080|2
/// ```
///
/// Use `--dry-run` to compile the Worker and ask Wrangler to validate the
/// generated configuration without uploading. Netlify and Vercel are also
/// available through `--target netlify` and `--target vercel`; Vercel accepts
/// `--runtime node` or `--runtime edge`.
class DeployCommand extends BaseCommand {
  /// Creates the deployment command.
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
        help: 'Dart library that exports the selected Worker factory.',
        valueHelp: 'package:my_app/app.dart',
      )
      ..addOption(
        'cloudflare-factory',
        help:
            'Cloudflare factory shape. Use environment when the app exports '
            'createCloudflareEngine(CloudflareEnvironment).',
        allowed: const ['engine', 'environment'],
        defaultsTo: 'engine',
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
      ..addMultiOption(
        'durable-object',
        help:
            'Cloudflare Durable Object binding. Use ClassName or '
            'BINDING=ClassName.',
        valueHelp: 'BINDING=ClassName',
      )
      ..addMultiOption(
        'd1',
        help: 'Cloudflare D1 binding. Use BINDING=DATABASE_NAME:DATABASE_ID.',
        valueHelp: 'BINDING=DATABASE_NAME:DATABASE_ID',
      )
      ..addMultiOption(
        'r2',
        help: 'Cloudflare R2 binding. Use BINDING=BUCKET_NAME.',
        valueHelp: 'BINDING=BUCKET_NAME',
      )
      ..addMultiOption(
        'queue',
        help: 'Cloudflare Queue producer. Use BINDING=QUEUE_NAME.',
        valueHelp: 'BINDING=QUEUE_NAME',
      )
      ..addMultiOption(
        'service',
        help: 'Cloudflare service binding. Use BINDING=SERVICE_NAME.',
        valueHelp: 'BINDING=SERVICE_NAME',
      )
      ..addMultiOption(
        'container',
        help:
            'Cloudflare Container binding. Use '
            'BINDING=CLASS_NAME|IMAGE|PORT|MAX_INSTANCES.',
        valueHelp: 'BINDING=CLASS_NAME|IMAGE|PORT|MAX_INSTANCES',
      )
      ..addMultiOption(
        'workflow',
        help:
            'Cloudflare Workflow binding. Use '
            'BINDING=WORKFLOW_NAME:CLASS_NAME[:SCRIPT_NAME].',
        valueHelp: 'BINDING=WORKFLOW_NAME:CLASS_NAME[:SCRIPT_NAME]',
      )
      ..addMultiOption(
        'secrets-store',
        help:
            'Cloudflare Secrets Store binding. '
            'Use BINDING=STORE_ID:SECRET_NAME.',
        valueHelp: 'BINDING=STORE_ID:SECRET_NAME',
      )
      ..addFlag(
        'dry-run',
        help: 'Build and validate without uploading.',
        negatable: false,
      )
      ..addFlag(
        'keep-vars',
        help: 'Keep variables configured in the Cloudflare dashboard.',
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
    final cloudflareFactory =
        results?['cloudflare-factory'] as String? ?? 'engine';
    if (target != 'cloudflare' && cloudflareFactory != 'engine') {
      throw UsageException(
        '--cloudflare-factory is only supported for Cloudflare deployments.',
        usage,
      );
    }
    final dartDurableObjects = _parseDurableObjectBindings(target);
    final containers = _parseContainerBindings(target);
    final durableObjects = _mergeDurableObjectBindings(
      dartDurableObjects,
      containers,
    );
    final d1Bindings = _parseD1Bindings(target);
    final r2Bindings = _parseSimpleCloudflareBindings(
      target,
      option: 'r2',
      resource: 'R2 bucket',
      valueHelp: 'BINDING=BUCKET_NAME',
    );
    final queueBindings = _parseSimpleCloudflareBindings(
      target,
      option: 'queue',
      resource: 'Queue',
      valueHelp: 'BINDING=QUEUE_NAME',
    );
    final serviceBindings = _parseSimpleCloudflareBindings(
      target,
      option: 'service',
      resource: 'Service',
      valueHelp: 'BINDING=SERVICE_NAME',
    );
    final workflowBindings = _parseWorkflowBindings(target);
    final secretsStoreBindings = _parseSecretsStoreBindings(target);

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
      generateCloudflareWorkerEntry(
        importPath: entry,
        factory: cloudflareFactory,
        durableObjectClasses: dartDurableObjects.map(
          (binding) => binding.className,
        ),
      ),
    );
    await _runDart(root, [
      'compile',
      'js',
      dartEntry.path,
      '-o',
      jsOutput.path,
      '-O2',
    ], label: 'Compiling Cloudflare Worker');
    await workerOutput.writeAsString(
      generateCloudflareWorkerWrapper(
        jsOutput.path,
        dartDurableObjects.map((binding) => binding.className),
        containerPorts: {
          for (final container in containers)
            container.className: container.port,
        },
      ),
    );

    final config = <String, Object?>{
      r'$schema':
          'https://developers.cloudflare.com/workers/wrangler/config-schema.json',
      'name': workerName,
      'main': p.basename(workerOutput.path),
      'compatibility_date': date,
      'compatibility_flags': ['nodejs_compat'],
    };
    if (durableObjects.isNotEmpty) {
      config['durable_objects'] = {
        'bindings': [
          for (final binding in durableObjects)
            {'name': binding.bindingName, 'class_name': binding.className},
        ],
      };
      config['migrations'] = [
        {
          'tag': 'routed-v1',
          'new_sqlite_classes': [
            for (final binding in durableObjects) binding.className,
          ],
        },
      ];
    }
    if (containers.isNotEmpty) {
      config['containers'] = [
        for (final container in containers)
          {
            'class_name': container.className,
            'image': _containerImageReference(root, buildRoot, container.image),
            if (container.maxInstances != null)
              'max_instances': container.maxInstances,
          },
      ];
    }
    if (d1Bindings.isNotEmpty) {
      config['d1_databases'] = [
        for (final binding in d1Bindings)
          {
            'binding': binding.bindingName,
            'database_name': binding.databaseName,
            'database_id': binding.databaseId,
          },
      ];
    }
    if (r2Bindings.isNotEmpty) {
      config['r2_buckets'] = [
        for (final binding in r2Bindings)
          {'binding': binding.bindingName, 'bucket_name': binding.resourceName},
      ];
    }
    if (queueBindings.isNotEmpty) {
      config['queues'] = {
        'producers': [
          for (final binding in queueBindings)
            {'binding': binding.bindingName, 'queue': binding.resourceName},
        ],
      };
    }
    if (serviceBindings.isNotEmpty) {
      config['services'] = [
        for (final binding in serviceBindings)
          {'binding': binding.bindingName, 'service': binding.resourceName},
      ];
    }
    if (workflowBindings.isNotEmpty) {
      config['workflows'] = [
        for (final binding in workflowBindings)
          {
            'name': binding.workflowName,
            'binding': binding.bindingName,
            'class_name': binding.className,
            if (binding.scriptName != null) 'script_name': binding.scriptName,
          },
      ];
    }
    if (secretsStoreBindings.isNotEmpty) {
      config['secrets_store_secrets'] = [
        for (final binding in secretsStoreBindings)
          {
            'binding': binding.bindingName,
            'store_id': binding.storeId,
            'secret_name': binding.secretName,
          },
      ];
    }
    await configOutput.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    final wranglerArgs = <String>['wrangler@latest', 'deploy'];
    if (dryRun) wranglerArgs.add('--dry-run');
    if (keepVars) wranglerArgs.add('--keep-vars');
    wranglerArgs
      ..add('--config')
      ..add(configOutput.path);
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
        .writeAsString('''
{
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
        .writeAsString('''
{
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
    final entry = functionRoot.fileSystem.file(
      p.join(functionRoot.path, 'entry.js'),
    );
    bundled
      ..copySync(entry.path)
      ..deleteSync();
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

  List<_CloudflareDurableObjectBinding> _parseDurableObjectBindings(
    String target,
  ) {
    final raw = results?['durable-object'];
    if (raw == null) return const [];
    if (target != 'cloudflare') {
      throw UsageException(
        '--durable-object is only supported for Cloudflare deployments.',
        usage,
      );
    }

    final values = raw is List ? raw.whereType<String>() : <String>[];
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final bindings = <_CloudflareDurableObjectBinding>[];
    for (final value in values) {
      final separator = value.indexOf('=');
      final className = (separator < 0 ? value : value.substring(separator + 1))
          .trim();
      final bindingName =
          (separator < 0
                  ? _defaultDurableObjectBindingName(className)
                  : value.substring(0, separator))
              .trim();
      if (!identifier.hasMatch(className)) {
        throw UsageException(
          'Invalid Durable Object class name "$className". Use a Dart '
          'identifier such as Counter.',
          usage,
        );
      }
      if (!identifier.hasMatch(bindingName)) {
        throw UsageException(
          'Invalid Durable Object binding name "$bindingName".',
          usage,
        );
      }
      if (bindings.any(
        (binding) =>
            binding.className == className ||
            binding.bindingName == bindingName,
      )) {
        throw UsageException(
          'Durable Object class and binding names must be unique: $value.',
          usage,
        );
      }
      bindings.add(
        _CloudflareDurableObjectBinding(
          bindingName: bindingName,
          className: className,
        ),
      );
    }
    return bindings;
  }

  List<_CloudflareD1Binding> _parseD1Bindings(String target) {
    final raw = results?['d1'];
    if (raw == null) return const [];
    if (target != 'cloudflare') {
      throw UsageException(
        '--d1 is only supported for Cloudflare deployments.',
        usage,
      );
    }

    final values = raw is List ? raw.whereType<String>() : <String>[];
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final bindings = <_CloudflareD1Binding>[];
    for (final value in values) {
      final equals = value.indexOf('=');
      if (equals < 1 || equals == value.length - 1) {
        throw UsageException(
          'Invalid D1 binding "$value". Use BINDING=DATABASE_NAME:DATABASE_ID.',
          usage,
        );
      }
      final bindingName = value.substring(0, equals).trim();
      final descriptor = value.substring(equals + 1).trim();
      final separator = descriptor.lastIndexOf(':');
      final databaseName = separator < 1
          ? ''
          : descriptor.substring(0, separator).trim();
      final databaseId = separator < 0
          ? ''
          : descriptor.substring(separator + 1).trim();
      if (!identifier.hasMatch(bindingName)) {
        throw UsageException('Invalid D1 binding name "$bindingName".', usage);
      }
      if (databaseName.isEmpty || databaseId.isEmpty) {
        throw UsageException(
          'Invalid D1 binding "$value". Use BINDING=DATABASE_NAME:DATABASE_ID.',
          usage,
        );
      }
      if (bindings.any((binding) => binding.bindingName == bindingName)) {
        throw UsageException(
          'D1 binding names must be unique: $bindingName.',
          usage,
        );
      }
      bindings.add(
        _CloudflareD1Binding(
          bindingName: bindingName,
          databaseName: databaseName,
          databaseId: databaseId,
        ),
      );
    }
    return bindings;
  }

  List<_CloudflareContainerBinding> _parseContainerBindings(String target) {
    final raw = results?['container'];
    if (raw == null) return const [];
    if (target != 'cloudflare') {
      throw UsageException(
        '--container is only supported for Cloudflare deployments.',
        usage,
      );
    }

    final values = raw is List ? raw.whereType<String>() : <String>[];
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final bindings = <_CloudflareContainerBinding>[];
    for (final value in values) {
      final equals = value.indexOf('=');
      final parts = equals < 1
          ? const <String>[]
          : value.substring(equals + 1).split('|');
      if (parts.length < 2 || parts.length > 4) {
        throw UsageException(
          'Invalid Container binding "$value". Use '
          'BINDING=CLASS_NAME|IMAGE[|PORT|MAX_INSTANCES].',
          usage,
        );
      }
      final bindingName = value.substring(0, equals).trim();
      final className = parts[0].trim();
      final image = parts[1].trim();
      final port = parts.length >= 3 ? int.tryParse(parts[2].trim()) : 8080;
      final maxInstances = parts.length >= 4
          ? int.tryParse(parts[3].trim())
          : null;
      if (!identifier.hasMatch(bindingName) ||
          !identifier.hasMatch(className)) {
        throw UsageException(
          'Invalid Container binding "$value". Binding and class names '
          'must be Dart/JavaScript identifiers.',
          usage,
        );
      }
      if (image.isEmpty || port == null || port < 1 || port > 65535) {
        throw UsageException(
          'Invalid Container binding "$value". The image must be non-empty '
          'and PORT must be between 1 and 65535.',
          usage,
        );
      }
      if (maxInstances != null && maxInstances < 1) {
        throw UsageException(
          'Invalid Container binding "$value". MAX_INSTANCES must be positive.',
          usage,
        );
      }
      if (bindings.any(
        (binding) =>
            binding.bindingName == bindingName ||
            binding.className == className,
      )) {
        throw UsageException(
          'Container binding and class names must be unique: $value.',
          usage,
        );
      }
      bindings.add(
        _CloudflareContainerBinding(
          bindingName: bindingName,
          className: className,
          image: image,
          port: port,
          maxInstances: maxInstances,
        ),
      );
    }
    return bindings;
  }

  List<_CloudflareDurableObjectBinding> _mergeDurableObjectBindings(
    List<_CloudflareDurableObjectBinding> dartBindings,
    List<_CloudflareContainerBinding> containers,
  ) {
    final result = [...dartBindings];
    for (final container in containers) {
      if (result.any(
        (binding) =>
            binding.bindingName == container.bindingName ||
            binding.className == container.className,
      )) {
        throw UsageException(
          'Container and Durable Object binding/class names must be unique: '
          '${container.bindingName}.',
          usage,
        );
      }
      result.add(
        _CloudflareDurableObjectBinding(
          bindingName: container.bindingName,
          className: container.className,
        ),
      );
    }
    return result;
  }

  List<_CloudflareWorkflowBinding> _parseWorkflowBindings(String target) {
    final raw = results?['workflow'];
    if (raw == null) return const [];
    if (target != 'cloudflare') {
      throw UsageException(
        '--workflow is only supported for Cloudflare deployments.',
        usage,
      );
    }

    final values = raw is List ? raw.whereType<String>() : <String>[];
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final bindings = <_CloudflareWorkflowBinding>[];
    for (final value in values) {
      final equals = value.indexOf('=');
      final parts = equals < 1
          ? const <String>[]
          : value.substring(equals + 1).split(':');
      if (parts.length < 2 || parts.length > 3) {
        throw UsageException(
          'Invalid Workflow binding "$value". Use '
          'BINDING=WORKFLOW_NAME:CLASS_NAME[:SCRIPT_NAME].',
          usage,
        );
      }
      final bindingName = value.substring(0, equals).trim();
      final workflowName = parts[0].trim();
      final className = parts[1].trim();
      final scriptName = parts.length == 3 ? parts[2].trim() : null;
      if (!identifier.hasMatch(bindingName) ||
          !identifier.hasMatch(className) ||
          workflowName.isEmpty ||
          (scriptName != null && scriptName.isEmpty)) {
        throw UsageException(
          'Invalid Workflow binding "$value". Binding and class names must '
          'be identifiers and the Workflow name must be non-empty.',
          usage,
        );
      }
      if (bindings.any((binding) => binding.bindingName == bindingName)) {
        throw UsageException(
          'Workflow binding names must be unique: $bindingName.',
          usage,
        );
      }
      bindings.add(
        _CloudflareWorkflowBinding(
          bindingName: bindingName,
          workflowName: workflowName,
          className: className,
          scriptName: scriptName,
        ),
      );
    }
    return bindings;
  }

  List<_CloudflareSecretsStoreBinding> _parseSecretsStoreBindings(
    String target,
  ) {
    final raw = results?['secrets-store'];
    if (raw == null) return const [];
    if (target != 'cloudflare') {
      throw UsageException(
        '--secrets-store is only supported for Cloudflare deployments.',
        usage,
      );
    }

    final values = raw is List ? raw.whereType<String>() : <String>[];
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final bindings = <_CloudflareSecretsStoreBinding>[];
    for (final value in values) {
      final equals = value.indexOf('=');
      final separator = value.lastIndexOf(':');
      final bindingName = equals < 1 ? '' : value.substring(0, equals).trim();
      final storeId = equals < 1 || separator <= equals
          ? ''
          : value.substring(equals + 1, separator).trim();
      final secretName = separator < 0
          ? ''
          : value.substring(separator + 1).trim();
      if (!identifier.hasMatch(bindingName) ||
          storeId.isEmpty ||
          secretName.isEmpty) {
        throw UsageException(
          'Invalid Secrets Store binding "$value". Use '
          'BINDING=STORE_ID:SECRET_NAME.',
          usage,
        );
      }
      if (bindings.any((binding) => binding.bindingName == bindingName)) {
        throw UsageException(
          'Secrets Store binding names must be unique: $bindingName.',
          usage,
        );
      }
      bindings.add(
        _CloudflareSecretsStoreBinding(
          bindingName: bindingName,
          storeId: storeId,
          secretName: secretName,
        ),
      );
    }
    return bindings;
  }

  List<_CloudflareSimpleBinding> _parseSimpleCloudflareBindings(
    String target, {
    required String option,
    required String resource,
    required String valueHelp,
  }) {
    final raw = results?[option];
    if (raw == null) return const [];
    if (target != 'cloudflare') {
      throw UsageException(
        '--$option is only supported for Cloudflare deployments.',
        usage,
      );
    }

    final values = raw is List ? raw.whereType<String>() : <String>[];
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final bindings = <_CloudflareSimpleBinding>[];
    for (final value in values) {
      final equals = value.indexOf('=');
      if (equals < 1 || equals == value.length - 1) {
        throw UsageException(
          'Invalid $resource binding "$value". Use $valueHelp.',
          usage,
        );
      }
      final bindingName = value.substring(0, equals).trim();
      final resourceName = value.substring(equals + 1).trim();
      if (!identifier.hasMatch(bindingName)) {
        throw UsageException(
          'Invalid $resource binding name "$bindingName".',
          usage,
        );
      }
      if (resourceName.isEmpty) {
        throw UsageException(
          'Invalid $resource binding "$value". Use $valueHelp.',
          usage,
        );
      }
      if (bindings.any((binding) => binding.bindingName == bindingName)) {
        throw UsageException(
          '$resource binding names must be unique: $bindingName.',
          usage,
        );
      }
      bindings.add(
        _CloudflareSimpleBinding(
          bindingName: bindingName,
          resourceName: resourceName,
        ),
      );
    }
    return bindings;
  }

  String _defaultDurableObjectBindingName(String className) => className
      .replaceAllMapped(
        RegExp('([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toUpperCase();

  String _containerImageReference(
    fs.Directory root,
    fs.Directory buildRoot,
    String image,
  ) {
    if (!image.startsWith('.') && !p.isAbsolute(image)) return image;
    final absolute = p.isAbsolute(image)
        ? p.normalize(image)
        : p.normalize(p.join(root.path, image));
    final relative = p.relative(absolute, from: buildRoot.path);
    return relative.startsWith('.') ? relative : './$relative';
  }

  String _sanitizeWorkerName(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9-]+'), '-')
        .replaceFirst(RegExp('^-+'), '')
        .replaceFirst(RegExp(r'-+$'), '');
    return normalized.isEmpty ? 'routed-worker' : normalized;
  }
}

final class _CloudflareDurableObjectBinding {
  const _CloudflareDurableObjectBinding({
    required this.bindingName,
    required this.className,
  });

  final String bindingName;
  final String className;
}

final class _CloudflareD1Binding {
  const _CloudflareD1Binding({
    required this.bindingName,
    required this.databaseName,
    required this.databaseId,
  });

  final String bindingName;
  final String databaseName;
  final String databaseId;
}

final class _CloudflareSimpleBinding {
  const _CloudflareSimpleBinding({
    required this.bindingName,
    required this.resourceName,
  });

  final String bindingName;
  final String resourceName;
}

final class _CloudflareContainerBinding {
  const _CloudflareContainerBinding({
    required this.bindingName,
    required this.className,
    required this.image,
    required this.port,
    required this.maxInstances,
  });

  final String bindingName;
  final String className;
  final String image;
  final int port;
  final int? maxInstances;
}

final class _CloudflareWorkflowBinding {
  const _CloudflareWorkflowBinding({
    required this.bindingName,
    required this.workflowName,
    required this.className,
    required this.scriptName,
  });

  final String bindingName;
  final String workflowName;
  final String className;
  final String? scriptName;
}

final class _CloudflareSecretsStoreBinding {
  const _CloudflareSecretsStoreBinding({
    required this.bindingName,
    required this.storeId,
    required this.secretName,
  });

  final String bindingName;
  final String storeId;
  final String secretName;
}

/// Generates the Dart Worker entrypoint used by a Cloudflare deployment.
///
/// [importPath] must identify the application library that exports the
/// selected factory. With the default `engine` factory, that library must
/// expose `createEngine`; with `environment`, it must expose
/// `createCloudflareEngine`. Names in [durableObjectClasses] are emitted as
/// registrations and must be exported by the same application library.
///
/// ```dart
/// final entry = generateCloudflareWorkerEntry(
///   importPath: 'package:todo_app/app.dart',
///   factory: 'environment',
///   durableObjectClasses: const ['Counter'],
/// );
/// ```
///
/// Throws an [ArgumentError] when [factory] is not `engine` or `environment`.
String generateCloudflareWorkerEntry({
  required String importPath,
  String factory = 'engine',
  Iterable<String> durableObjectClasses = const <String>[],
}) {
  final factorySource = switch (factory) {
    'engine' => 'defineCloudflareFetchFactoryAsync(app.createEngine);',
    'environment' =>
      'defineCloudflareFetchFactoryWithEnvironmentAsync('
          'app.createCloudflareEngine);',
    _ => throw ArgumentError.value(
      factory,
      'factory',
      'must be engine or environment',
    ),
  };
  final classes = durableObjectClasses.toList(growable: false);
  final registration = classes.isEmpty
      ? ''
      : '''
  defineCloudflareDurableObjects({
${classes.map((name) => "    '$name': app.$name.new,").join('\n')}
  });
''';
  return '''
import 'package:routed_node/cloudflare.dart';
import '$importPath' as app;

void main() {
$registration  $factorySource
}
''';
}

/// Generates the JavaScript wrapper that exports Cloudflare bindings.
///
/// [compiledPath] is the path to the Dart-compiled Worker JavaScript. The
/// generated wrapper imports its basename, exposes each class in
/// [durableObjectClasses] as a Durable Object class, and exposes container
/// classes from [containerPorts] using their configured TCP port. The result
/// is intended to be written as the Wrangler `main` file alongside the
/// compiled JavaScript.
///
/// ```dart
/// final wrapper = generateCloudflareWorkerWrapper(
///   '.dart_tool/routed/deploy/cloudflare/worker.dart.js',
///   const ['Counter'],
///   containerPorts: const {'ApiContainer': 8080},
/// );
/// ```
String generateCloudflareWorkerWrapper(
  String compiledPath,
  Iterable<String> durableObjectClasses, {
  Map<String, int> containerPorts = const <String, int>{},
}) {
  final relative = p.basename(compiledPath);
  final exports = durableObjectClasses
      .map((className) {
        // Generated JavaScript is intentionally emitted without a leading
        // newline so the wrapper remains stable for deployment tooling.
        // ignore: leading_newlines_in_multiline_strings
        return '''export class $className {
  constructor(state, env) {
    const factory = __routedDurableObjects['$className'];
    if (typeof factory !== 'function') {
      throw new Error('No Routed Durable Object factory registered for $className.');
    }
    this.delegate = factory(state, env);
  }

  fetch(request) {
    return this.delegate.fetch(request);
  }

  alarm() {
    return this.delegate.alarm();
  }

  webSocketMessage(webSocket, message) {
    return this.delegate.webSocketMessage(webSocket, message);
  }

  webSocketClose(webSocket, code, reason, wasClean) {
    return this.delegate.webSocketClose(webSocket, code, reason, wasClean);
  }

  webSocketError(webSocket, error) {
    return this.delegate.webSocketError(webSocket, error);
  }
}''';
      })
      .join('\n\n');
  final containerExports = containerPorts.entries
      .map((entry) {
        // Generated JavaScript is intentionally emitted without a leading
        // newline so the wrapper remains stable for deployment tooling.
        // ignore: leading_newlines_in_multiline_strings
        return '''export class ${entry.key} {
  constructor(state, env) {
    if (!state.container) {
      throw new Error('Cloudflare Container state is unavailable for ${entry.key}.');
    }
    this.container = state.container;
    this.container.start();
  }

  fetch(request) {
    return this.container.getTcpPort(${entry.value}).fetch(request);
  }
}''';
      })
      .join('\n\n');
  final sections = [
    if (exports.isNotEmpty) exports,
    if (containerExports.isNotEmpty) containerExports,
  ].join('\n\n');
  return '''
import './$relative';

const __routedDurableObjects =
    globalThis.__routed_durable_objects__ ?? {};

$sections

export default {
  async fetch(request, env, ctx) {
    return await globalThis.__routed_fetch__(request, ctx, env);
  },
};
''';
}
