import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:routed_cli/src/console/args/commands/deploy.dart';
import 'package:routed_cli/src/console/args/runner.dart';
import 'package:test/test.dart';

void main() {
  test('deploy command exposes the seamless cloudflare workflow', () async {
    final fs = MemoryFileSystem();
    final command = DeployCommand(fileSystem: fs);
    final root = fs.directory('/workspace/app')..createSync(recursive: true);
    fs.currentDirectory = root;
    final pubspec = fs.file('${root.path}/pubspec.yaml')
      ..createSync()
      ..writeAsStringSync(
        'name: demo_app\ndependencies:\n  routed_node: ^0.1.0\n',
      );

    final runner = RoutedCommandRunner()..register([command]);

    expect(runner.commands['deploy'], isNotNull);
    expect(pubspec.readAsStringSync(), contains('routed_node'));

    final parsed = command.argParser.parse([
      '--cloudflare-factory',
      'environment',
      '--ssr-entry',
      'build/react/ssr.entry.mjs',
      '--var',
      'AUTH_ORIGIN=https://example.workers.dev',
      '--durable-object',
      'COUNTER=Counter',
      '--durable-object',
      'ROOM=ChatRoom',
      '--d1',
      'DB=routed-node-api-demo:database-id',
      '--r2',
      'FILES=app-files',
      '--queue',
      'EVENTS=app-events',
      '--service',
      'PROFILE_API=profile-api',
      '--container',
      'APP=AppContainer|./Dockerfile|8080|3',
      '--workflow',
      'BILLING=billing-workflow:BillingWorkflow:billing-worker',
      '--secrets-store',
      'API_SECRET=store-1:API_KEY',
    ]);
    expect(parsed['durable-object'], ['COUNTER=Counter', 'ROOM=ChatRoom']);
    expect(parsed['cloudflare-factory'], 'environment');
    expect(parsed['ssr-entry'], 'build/react/ssr.entry.mjs');
    expect(parsed['var'], ['AUTH_ORIGIN=https://example.workers.dev']);
    expect(parsed['d1'], ['DB=routed-node-api-demo:database-id']);
    expect(parsed['r2'], ['FILES=app-files']);
    expect(parsed['queue'], ['EVENTS=app-events']);
    expect(parsed['service'], ['PROFILE_API=profile-api']);
    expect(parsed['container'], ['APP=AppContainer|./Dockerfile|8080|3']);
    expect(parsed['workflow'], [
      'BILLING=billing-workflow:BillingWorkflow:billing-worker',
    ]);
    expect(parsed['secrets-store'], ['API_SECRET=store-1:API_KEY']);
  });

  test('Cloudflare deployment sources register and export Durable Objects', () {
    final entry = generateCloudflareWorkerEntry(
      importPath: 'package:demo_app/app.dart',
      durableObjectClasses: ['Counter', 'ChatRoom'],
    );
    expect(entry, contains("'Counter': app.Counter.new"));
    expect(entry, contains("'ChatRoom': app.ChatRoom.new"));
    expect(entry, contains('defineCloudflareFetchFactoryAsync'));

    final environmentEntry = generateCloudflareWorkerEntry(
      importPath: 'package:demo_app/app.dart',
      factory: 'environment',
    );
    expect(
      environmentEntry,
      contains('defineCloudflareFetchFactoryWithEnvironmentAsync'),
    );
    expect(environmentEntry, contains('app.createCloudflareEngine'));

    final wrapper = generateCloudflareWorkerWrapper('/tmp/worker.dart.js', [
      'Counter',
      'ChatRoom',
    ]);
    expect(wrapper, contains('export class Counter'));
    expect(wrapper, contains('export class ChatRoom'));
    expect(wrapper, contains('globalThis.__routed_durable_objects__'));
    expect(wrapper, contains('this.delegate.fetch(request)'));
    expect(wrapper, contains('this.delegate.webSocketMessage'));
    expect(wrapper, contains('this.delegate.webSocketClose'));
    expect(wrapper, contains('this.delegate.webSocketError'));

    final containerWrapper = generateCloudflareWorkerWrapper(
      '/tmp/worker.dart.js',
      const [],
      containerPorts: {'AppContainer': 8080},
    );
    expect(containerWrapper, contains('export class AppContainer'));
    expect(containerWrapper, contains('getTcpPort(8080)'));
    expect(containerWrapper, contains('this.container.start()'));

    final ssrWrapper = generateCloudflareWorkerWrapper(
      '/tmp/worker.dart.js',
      const [],
      ssrEntry: 'frontend/ssr.entry.mjs',
    );
    expect(
      ssrWrapper,
      contains("import frontendSsr from './frontend/ssr.entry.mjs';"),
    );
    expect(ssrWrapper, contains("pathname === '/__ssr'"));
    expect(ssrWrapper, contains('frontendSsr.fetch(request, env, ctx)'));
  });

  test('frontend SSR deployment uploads the complete build', () async {
    final fs = MemoryFileSystem();
    final root = fs.directory('/workspace/app')..createSync(recursive: true);
    fs.currentDirectory = root;
    fs.file('${root.path}/pubspec.yaml')
      ..createSync()
      ..writeAsStringSync(
        'name: demo_app\ndependencies:\n  routed_node: ^0.1.0\n',
      );
    fs.file('${root.path}/lib/cloudflare_app.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('Future<Object> createEngine() async => Object();');
    fs.file('${root.path}/build/site/ssr.entry.mjs')
      ..createSync(recursive: true)
      ..writeAsStringSync('export default {};');
    fs.file('${root.path}/build/site/index.html')
      ..createSync(recursive: true)
      ..writeAsStringSync('<!doctype html>');
    fs.file('${root.path}/build/site/assets/app.js')
      ..createSync(recursive: true)
      ..writeAsStringSync('console.log("frontend");');

    final processes = <(String, List<String>, String)>[];
    final command = DeployCommand(
      fileSystem: fs,
      processRunner: (executable, arguments, workingDirectory) async {
        processes.add((executable, arguments, workingDirectory));
        if (executable == 'dart' && arguments.contains('compile')) {
          fs.file(
              '${root.path}/.dart_tool/routed/deploy/cloudflare/worker.dart.js',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync(
              'globalThis.__routed_fetch__ = () => new Response();',
            );
        }
        return 0;
      },
    );
    final runner = RoutedCommandRunner()..register([command]);

    await runner.run([
      'deploy',
      '--dry-run',
      '--target',
      'cloudflare',
      '--entry',
      'package:demo_app/cloudflare_app.dart',
      '--ssr-entry',
      'build/site/ssr.entry.mjs',
    ]);

    final config =
        jsonDecode(
              fs
                  .file(
                    '${root.path}/.dart_tool/routed/deploy/cloudflare/wrangler.jsonc',
                  )
                  .readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(config['compatibility_flags'], [
      'nodejs_compat',
      'global_fetch_strictly_public',
    ]);
    expect(config['assets'], {
      'directory': 'frontend',
      'binding': 'ASSETS',
      'run_worker_first': true,
    });
    expect(
      fs
          .file(
            '${root.path}/.dart_tool/routed/deploy/cloudflare/frontend/index.html',
          )
          .readAsStringSync(),
      '<!doctype html>',
    );
    expect(
      fs
          .file(
            '${root.path}/.dart_tool/routed/deploy/cloudflare/frontend/assets/app.js',
          )
          .readAsStringSync(),
      contains('frontend'),
    );
  });

  test('Cloudflare dry-run validates and writes all binding sections', () async {
    final fs = MemoryFileSystem();
    final root = fs.directory('/workspace/app')..createSync(recursive: true);
    fs.currentDirectory = root;
    fs.file('${root.path}/pubspec.yaml')
      ..createSync()
      ..writeAsStringSync(
        'name: demo_app\ndependencies:\n  routed_node: ^0.1.0\n',
      );
    final processes = <(String, List<String>, String)>[];
    final command = DeployCommand(
      fileSystem: fs,
      processRunner: (executable, arguments, workingDirectory) async {
        processes.add((executable, arguments, workingDirectory));
        return 0;
      },
    );
    final runner = RoutedCommandRunner()..register([command]);

    await runner.run([
      'deploy',
      '--dry-run',
      '--var',
      'AUTH_ORIGIN=https://example.workers.dev',
      '--var',
      'FEATURE_FLAG=enabled',
      '--d1',
      'AUTH_DB=auth-db:database-id',
      '--r2',
      'ASSETS=app-assets',
    ]);

    final config =
        jsonDecode(
              fs
                  .file(
                    '${root.path}/.dart_tool/routed/deploy/cloudflare/wrangler.jsonc',
                  )
                  .readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(config['vars'], {
      'AUTH_ORIGIN': 'https://example.workers.dev',
      'FEATURE_FLAG': 'enabled',
    });
    expect(config['d1_databases'], [
      {
        'binding': 'AUTH_DB',
        'database_name': 'auth-db',
        'database_id': 'database-id',
      },
    ]);
    expect(config['r2_buckets'], [
      {'binding': 'ASSETS', 'bucket_name': 'app-assets'},
    ]);
    expect(processes.first.$1, endsWith('dart'));
    expect(processes.last.$1, 'npx');
    expect(processes.last.$2, contains('--dry-run'));
  });

  test(
    'Cloudflare deployment rejects invalid variable and binding names',
    () async {
      final fs = MemoryFileSystem();
      final root = fs.directory('/workspace/app')..createSync(recursive: true);
      fs.currentDirectory = root;
      fs.file('${root.path}/pubspec.yaml')
        ..createSync()
        ..writeAsStringSync(
          'name: demo_app\ndependencies:\n  routed_node: ^0.1.0\n',
        );

      Future<void> expectUsage(List<String> arguments) async {
        final command = DeployCommand(
          fileSystem: fs,
          processRunner: (_, _, _) async => 0,
        );
        final runner = RoutedCommandRunner()..register([command]);
        await expectLater(
          runner.run(['deploy', '--dry-run', ...arguments]),
          throwsA(isA<UsageException>()),
        );
      }

      await expectUsage(['--var', 'AUTH_ORIGIN=   ']);
      await expectUsage([
        '--var',
        'AUTH_DB=enabled',
        '--d1',
        'AUTH_DB=auth-db:database-id',
      ]);
      await expectUsage(['--target', 'netlify', '--var', 'AUTH_ORIGIN=value']);
    },
  );
}
