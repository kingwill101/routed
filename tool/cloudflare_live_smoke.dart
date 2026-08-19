import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _usage = '''
Run Routed's Cloudflare binding smoke test against disposable remote resources.

Usage:
  dart run tool/cloudflare_live_smoke.dart --deploy

Options:
  --deploy       Provision resources, deploy fixture Workers, and run HTTP checks.
  --keep         Keep the temporary Cloudflare resources after the run.
  --name NAME    Worker name (defaults to routed-live-<timestamp>).
  --containers   Attempt the Container check when the account is entitled to it.
  --help         Show this help.
''';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.write(_usage);
    return;
  }
  if (!options.deploy) {
    stdout.write('Pass --deploy to provision and run the live smoke test.\n');
    stdout.write(_usage);
    return;
  }

  final root = Directory.current.absolute;
  final sample = Directory(
    p.join(root.path, 'packages', 'routed_node', 'example', 'api'),
  );
  final toolDirectory = Directory(p.join(root.path, 'tool'));
  final temp = await Directory.systemTemp.createTemp('routed-cloudflare-live-');
  final prefix = _resourcePrefix();
  final resources = _Resources(
    prefix: prefix,
    workerName: options.workerName ?? prefix,
  );

  try {
    stdout.writeln('Provisioning disposable Cloudflare resources…');
    await _provision(resources);
    await _executeD1Schema(resources);

    await _deployFixtureWorker(
      temp: temp,
      source: File(p.join(toolDirectory.path, 'cloudflare_live_service.js')),
      name: resources.serviceName,
      config: {
        r'$schema':
            'https://developers.cloudflare.com/workers/wrangler/config-schema.json',
        'name': resources.serviceName,
        'main': p.join(temp.path, 'service.js'),
        'compatibility_date': _compatibilityDate(),
      },
    );
    resources.serviceDeployed = true;
    await _deployFixtureWorker(
      temp: temp,
      source: File(p.join(toolDirectory.path, 'cloudflare_live_workflow.js')),
      name: resources.workflowWorkerName,
      config: {
        r'$schema':
            'https://developers.cloudflare.com/workers/wrangler/config-schema.json',
        'name': resources.workflowWorkerName,
        'main': p.join(temp.path, 'workflow.js'),
        'compatibility_date': _compatibilityDate(),
        'workflows': [
          {
            'name': resources.workflowName,
            'binding': 'SMOKE_WORKFLOW',
            'class_name': 'RoutedLiveWorkflow',
          },
        ],
      },
    );
    resources.workflowDeployed = true;

    final containerEnabled = options.containers && await _containerAccess();
    if (options.containers && !containerEnabled) {
      stdout.writeln(
        'Container check: skipped because this account is not entitled to '
        'Cloudflare Containers.',
      );
    }

    final deployOutput = await _deployRoutedSample(
      root: root,
      sample: sample,
      resources: resources,
      containerEnabled: containerEnabled,
    );
    final workerUrl = _workerUrl(deployOutput, resources.workerName);
    stdout.writeln('Live Worker: $workerUrl');
    await _runChecks(workerUrl, resources, containerEnabled: containerEnabled);
    stdout.writeln('Cloudflare live smoke test passed.');
  } finally {
    if (options.keep) {
      stdout.writeln(
        'Keeping resources. Worker: ${resources.workerName}; '
        'D1: ${resources.d1Name}; R2: ${resources.bucketName}; '
        'Queue: ${resources.queueName}.',
      );
    } else {
      await _cleanup(resources);
    }
    await temp.delete(recursive: true);
  }
}

final class _Options {
  const _Options({
    required this.deploy,
    required this.keep,
    required this.workerName,
    required this.containers,
    required this.help,
  });

  final bool deploy;
  final bool keep;
  final String? workerName;
  final bool containers;
  final bool help;

  static _Options parse(List<String> args) {
    var deploy = false;
    var keep = false;
    var containers = false;
    var help = false;
    String? workerName;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--deploy':
          deploy = true;
        case '--keep':
          keep = true;
        case '--containers':
          containers = true;
        case '--help' || '-h':
          help = true;
        case '--name':
          if (i + 1 >= args.length) {
            throw ArgumentError('--name requires a value.');
          }
          workerName = args[++i];
        default:
          throw ArgumentError('Unknown option: ${args[i]}');
      }
    }
    return _Options(
      deploy: deploy,
      keep: keep,
      workerName: workerName,
      containers: containers,
      help: help,
    );
  }
}

final class _Resources {
  _Resources({required this.prefix, required this.workerName});

  final String prefix;
  final String workerName;
  late final String d1Name = '$prefix-d1';
  late final String bucketName = '$prefix-bucket';
  late final String queueName = '$prefix-queue';
  late final String serviceName = '$prefix-service';
  late final String workflowWorkerName = '$prefix-workflow';
  late final String workflowName = '$prefix-workflow';
  late final String storeName = '$prefix-store';
  late final String secretName = '${prefix.replaceAll('-', '_')}_secret';
  late final String r2Key = 'routed-live/$workerName.txt';

  String? d1Id;
  String? storeId;
  String? secretId;
  bool d1Created = false;
  bool bucketCreated = false;
  bool queueCreated = false;
  bool storeCreated = false;
  bool secretCreated = false;
  bool serviceDeployed = false;
  bool workflowDeployed = false;
  bool workerDeployed = false;
}

String _resourcePrefix() {
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  return 'routed-live-${stamp.toRadixString(36)}';
}

String _compatibilityDate() =>
    DateTime.now().toUtc().toIso8601String().substring(0, 10);

Future<void> _provision(_Resources resources) async {
  final d1 = await _wrangler(['d1', 'create', resources.d1Name]);
  resources.d1Id = _uuidFrom(d1);
  resources.d1Created = true;

  await _wrangler(['r2', 'bucket', 'create', resources.bucketName]);
  resources.bucketCreated = true;

  await _wrangler(['queues', 'create', resources.queueName]);
  resources.queueCreated = true;

  final stores = await _wrangler([
    'secrets-store',
    'store',
    'list',
    '--remote',
    '--per-page',
    '100',
  ], allowFailure: true);
  if (stores.exitCode == 0) {
    resources.storeId = _hexIdFrom(stores);
  }
  if (resources.storeId == null) {
    final created = await _wrangler([
      'secrets-store',
      'store',
      'create',
      resources.storeName,
      '--remote',
    ]);
    resources.storeId = _hexIdAfterLabel(created, 'ID');
    resources.storeCreated = true;
  }
  final storeId = resources.storeId;
  if (storeId == null) {
    throw StateError('Cloudflare did not return a Secrets Store ID.');
  }

  final secret = await _wrangler([
    'secrets-store',
    'secret',
    'create',
    storeId,
    '--name',
    resources.secretName,
    '--value',
    'routed-secrets-store-ok',
    '--scopes',
    'workers',
    '--remote',
  ]);
  resources.secretId = _hexIdAfterLabel(secret, 'ID');
  resources.secretCreated = true;
  await _waitForSecret(resources);
}

Future<void> _waitForSecret(_Resources resources) async {
  final storeId = resources.storeId;
  if (storeId == null) {
    throw StateError('Cloudflare did not return a Secrets Store ID.');
  }

  for (var attempt = 1; attempt <= 30; attempt++) {
    final result = await _wrangler([
      'secrets-store',
      'secret',
      'list',
      storeId,
      '--remote',
      '--per-page',
      '100',
    ], allowFailure: true);
    final output = _stripAnsi('${result.stdout}\n${result.stderr}');
    final row = output
        .split('\n')
        .where((line) => line.contains(resources.secretName))
        .join(' ')
        .toLowerCase();
    if (result.exitCode == 0 && row.contains('active')) {
      stdout.writeln('Secrets Store secret is active.');
      return;
    }
    if (row.contains('deleted')) {
      throw StateError('Cloudflare marked the live smoke secret deleted.');
    }
    if (attempt == 30) {
      throw StateError(
        'Cloudflare Secrets Store secret did not become active.\n$output',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

Future<void> _executeD1Schema(_Resources resources) async {
  await _wrangler([
    'd1',
    'execute',
    resources.d1Name,
    '--remote',
    '--yes',
    '--command',
    'CREATE TABLE IF NOT EXISTS routed_live_checks '
        '(id INTEGER PRIMARY KEY AUTOINCREMENT, marker TEXT NOT NULL)',
  ]);
}

Future<void> _deployFixtureWorker({
  required Directory temp,
  required File source,
  required String name,
  required Map<String, Object?> config,
}) async {
  final sourceName = p.basename(source.path);
  await File(
    p.join(temp.path, sourceName),
  ).writeAsString(await source.readAsString());
  final configPath = p.join(temp.path, '$name.wrangler.jsonc');
  final effectiveConfig = {...config, 'main': p.join(temp.path, sourceName)};
  await File(
    configPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(effectiveConfig));
  final result = await _wrangler([
    'deploy',
    '--config',
    configPath,
  ], workingDirectory: temp.path);
  if (name.endsWith('-workflow')) {
    // A successful deployment is enough to establish the cross-Worker
    // Workflow binding used by the Routed sample.
    if (result.exitCode != 0) throw StateError('Workflow deployment failed.');
  }
}

Future<ProcessResult> _deployRoutedSample({
  required Directory root,
  required Directory sample,
  required _Resources resources,
  required bool containerEnabled,
}) async {
  final cli = p.join(root.path, 'packages', 'routed_cli', 'bin', 'routed.dart');
  final d1Id = resources.d1Id;
  final storeId = resources.storeId;
  if (d1Id == null || storeId == null) {
    throw StateError('Live resource provisioning did not complete.');
  }

  final args = <String>[
    'run',
    cli,
    'deploy',
    '--target',
    'cloudflare',
    '--name',
    resources.workerName,
    '--d1',
    'DB=${resources.d1Name}:$d1Id',
    '--durable-object',
    'COUNTER=Counter',
    '--r2',
    'FILES=${resources.bucketName}',
    '--queue',
    'EVENTS=${resources.queueName}',
    '--service',
    'PROFILE_API=${resources.serviceName}',
    '--workflow',
    'SMOKE_WORKFLOW=${resources.workflowName}:RoutedLiveWorkflow:${resources.workflowWorkerName}',
    '--secrets-store',
    'SMOKE_SECRET=$storeId:${resources.secretName}',
  ];
  if (containerEnabled) {
    args.addAll([
      '--container',
      'APP=AppContainer|${p.join(root.path, 'tool', 'cloudflare_live_container', 'Dockerfile')}|8080|1',
    ]);
  }

  final result = await Process.run(
    'dart',
    args,
    workingDirectory: sample.path,
    runInShell: false,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw StateError('Routed Cloudflare deployment failed.');
  }
  resources.workerDeployed = true;
  return result;
}

Future<bool> _containerAccess() async {
  final result = await _wrangler(['containers', 'list'], allowFailure: true);
  return result.exitCode == 0;
}

String _workerUrl(ProcessResult result, String workerName) {
  final output = _stripAnsi('${result.stdout}\n${result.stderr}');
  final match = RegExp(r'https://[^\s]+\.workers\.dev').firstMatch(output);
  if (match != null) return match.group(0)!;
  throw StateError(
    'Wrangler deployed $workerName but did not report a workers.dev URL.',
  );
}

Future<void> _runChecks(
  String baseUrl,
  _Resources resources, {
  required bool containerEnabled,
}) async {
  final checks = <String, Future<bool> Function(Map<String, dynamic>)>{
    '/health': (body) => Future.value(body['ok'] == true),
    '/bindings/request': (body) => Future.value(body['ok'] == true),
    '/bindings/cache': (body) => Future.value(body['ok'] == true),
    '/bindings/d1': (body) => Future.value(body['ok'] == true),
    '/bindings/durable-object': (body) => Future.value(body['ok'] == true),
    '/bindings/r2?key=${Uri.encodeComponent(resources.r2Key)}': (body) =>
        Future.value(body['ok'] == true && body['listed'] == true),
    '/bindings/queue': (body) => Future.value(body['ok'] == true),
    '/bindings/service': (body) => Future.value(
      body['ok'] == true &&
          body['rpc'] == 5 &&
          body['constant'] == 5 &&
          body['greeting'] == 'hello Ada',
    ),
    '/bindings/secrets-store': (body) =>
        Future.value(body['ok'] == true && body['present'] == true),
    '/bindings/workflow': (body) =>
        Future.value(body['ok'] == true && body['id'] is String),
  };
  if (containerEnabled) {
    checks['/bindings/container'] = (body) => Future.value(body['ok'] == true);
  }

  final client = HttpClient();
  try {
    await _waitForWorker(client, baseUrl);
    for (final entry in checks.entries) {
      final response = await _get(client, '$baseUrl${entry.key}');
      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw StateError(
          '${entry.key}: expected JSON, got HTTP ${response.status}: '
          '${response.body}',
        );
      }
      if (response.status != 200 || !await entry.value(body)) {
        throw StateError('${entry.key}: HTTP ${response.status} $body');
      }
      stdout.writeln('  PASS ${entry.key}');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _waitForWorker(HttpClient client, String baseUrl) async {
  for (var attempt = 1; attempt <= 30; attempt++) {
    final response = await _get(client, '$baseUrl/health');
    if (response.status == 200) return;
    if (attempt == 30) {
      throw StateError(
        'Worker did not become ready: HTTP ${response.status} '
        '${response.body}',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

Future<({int status, String body})> _get(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close().timeout(const Duration(seconds: 15));
  final body = await response.transform(utf8.decoder).join();
  return (status: response.statusCode, body: body);
}

Future<void> _cleanup(_Resources resources) async {
  stdout.writeln('Cleaning up disposable Cloudflare resources…');
  await _tryCleanup(resources.workerDeployed, [
    'delete',
    resources.workerName,
    '--force',
  ]);
  await _tryCleanup(resources.workflowDeployed, [
    'delete',
    resources.workflowWorkerName,
    '--force',
  ]);
  await _tryCleanup(resources.workflowDeployed, [
    'workflows',
    'delete',
    resources.workflowName,
  ]);
  await _tryCleanup(resources.serviceDeployed, [
    'delete',
    resources.serviceName,
    '--force',
  ]);
  if (resources.secretCreated &&
      resources.storeId != null &&
      resources.secretId != null) {
    await _tryCleanup(true, [
      'secrets-store',
      'secret',
      'delete',
      resources.storeId!,
      '--secret-id',
      resources.secretId!,
      '--remote',
    ]);
  }
  if (resources.storeCreated && resources.storeId != null) {
    await _tryCleanup(true, [
      'secrets-store',
      'store',
      'delete',
      resources.storeId!,
      '--remote',
    ]);
  }
  await _tryCleanup(resources.queueCreated, [
    'queues',
    'delete',
    resources.queueName,
  ]);
  await _tryCleanup(resources.bucketCreated, [
    'r2',
    'bucket',
    'delete',
    resources.bucketName,
  ]);
  if (resources.d1Created) {
    await _tryCleanup(true, [
      'd1',
      'delete',
      resources.d1Name,
      '--skip-confirmation',
    ]);
  }
}

Future<void> _tryCleanup(bool needed, List<String> args) async {
  if (!needed) return;
  final result = await _wrangler(args, allowFailure: true);
  if (result.exitCode != 0) {
    stderr.writeln('Cleanup warning for ${args.join(' ')}');
  }
}

Future<ProcessResult> _wrangler(
  List<String> args, {
  bool allowFailure = false,
  String? workingDirectory,
}) async {
  final result = await Process.run(
    'npx',
    ['--yes', 'wrangler@latest', ...args],
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  final output = _stripAnsi('${result.stdout}\n${result.stderr}');
  if (output.trim().isNotEmpty) stdout.write(output);
  if (result.exitCode != 0 && !allowFailure) {
    throw StateError('Wrangler command failed: ${args.join(' ')}');
  }
  return result;
}

String? _uuidFrom(ProcessResult result) {
  final output = _stripAnsi('${result.stdout}\n${result.stderr}');
  final matches = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b',
  ).allMatches(output).toList();
  return matches.isEmpty ? null : matches.last.group(0);
}

String? _hexIdFrom(ProcessResult result) {
  final output = _stripAnsi('${result.stdout}\n${result.stderr}');
  final matches = RegExp(r'\b[0-9a-fA-F]{32}\b').allMatches(output).toList();
  return matches.isEmpty ? null : matches.last.group(0);
}

String? _hexIdAfterLabel(ProcessResult result, String label) {
  final output = _stripAnsi('${result.stdout}\n${result.stderr}');
  final match = RegExp(
    '$label\\s*:\\s*([0-9a-fA-F]{32})',
    caseSensitive: false,
  ).firstMatch(output);
  return match?.group(1);
}

String _stripAnsi(String value) =>
    value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
