import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'app.dart' as app;
import 'platform/platform_runtime.dart';

class PlatformE2eCommand extends Command<void> {
  @override
  String get name => 'platform:e2e';

  @override
  String get description =>
      'Run the complete in-memory platform and Stem worker flow.';

  @override
  String get summary => 'Submit a task and wait for the Stem worker result.';

  @override
  String get category => 'Platform';

  @override
  Future<void> run() async {
    final engine = await app.createEngine();
    try {
      final runtime = await engine.make<PlatformRuntime>();
      final task = await runtime.submit(
        tenant: runtime.config.defaultTenant,
        namespace: runtime.config.defaultNamespace,
        idempotencyKey: 'cli-e2e-task',
        message: 'hello from routed_cli',
      );
      final result = await runtime.waitForTask(task.id);

      stdout.writeln('task=${task.id}');
      stdout.writeln('result=$result');
    } finally {
      await engine.close();
    }
  }
}

FutureOr<List<Command<void>>> buildProjectCommands() {
  return [PlatformE2eCommand()];
}
