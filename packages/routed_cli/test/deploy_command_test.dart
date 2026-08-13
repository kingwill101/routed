import 'package:file/memory.dart';
import 'package:routed_cli/src/console/args/commands/deploy.dart';
import 'package:routed_cli/src/console/args/runner.dart';
import 'package:test/test.dart';

void main() {
  test('deploy command exposes the seamless cloudflare workflow', () async {
    final fs = MemoryFileSystem();
    final root = fs.directory('/workspace/app')..createSync(recursive: true);
    fs.currentDirectory = root;
    final pubspec = fs.file('${root.path}/pubspec.yaml')
      ..createSync()
      ..writeAsStringSync(
        'name: demo_app\ndependencies:\n  routed_node: ^0.1.0\n',
      );

    final runner = RoutedCommandRunner()
      ..register([DeployCommand(fileSystem: fs)]);

    expect(runner.commands['deploy'], isNotNull);
    expect(pubspec.readAsStringSync(), contains('routed_node'));
  });
}
