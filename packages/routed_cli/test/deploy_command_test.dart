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
  });
}
