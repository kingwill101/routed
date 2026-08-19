import 'package:stem/stem.dart';

import 'platform_config.dart';

/// A process-local control/execution plane used by the reference example.
///
/// The maps model the metadata that would normally live in a durable control
/// plane. Stem owns task execution and result state through its in-memory
/// broker and result backend.
final class PlatformRuntime {
  PlatformRuntime(this.config)
    : _broker = InMemoryBroker(),
      _backend = InMemoryResultBackend() {
    final handler = FunctionTaskHandler<Map<String, Object?>>.inline(
      name: 'platform.echo',
      entrypoint: _echo,
    );
    _stem = Stem(broker: _broker, backend: _backend, tasks: [handler]);
    _worker = Worker(
      broker: _broker,
      backend: _backend,
      tasks: [handler],
      concurrency: 1,
      consumerName: 'routed-platform-worker',
    );
  }

  final PlatformConfig config;
  final InMemoryBroker _broker;
  final InMemoryResultBackend _backend;
  late final Stem _stem;
  late final Worker _worker;
  final Map<String, PlatformTask> _tasks = {};
  final Map<String, String> _idempotency = {};
  bool _started = false;
  bool _closed = false;

  Future<void> start() async {
    if (_started) return;
    if (_closed) throw StateError('Platform runtime is closed');
    await _worker.start();
    _started = true;
  }

  Future<PlatformTask> submit({
    required String tenant,
    required String namespace,
    required String idempotencyKey,
    required String message,
  }) async {
    _ensureOpen();
    if (tenant != config.defaultTenant ||
        namespace != config.defaultNamespace) {
      throw StateError('Tenant or namespace is not available in this example');
    }

    final key = '$tenant/$namespace/$idempotencyKey';
    final existingId = _idempotency[key];
    if (existingId != null) {
      final existing = _tasks[existingId]!;
      if (existing.message != message) {
        throw StateError('Idempotency key was reused with a different payload');
      }
      return existing;
    }

    final taskId = await _stem.enqueue(
      'platform.echo',
      args: {'message': message},
      headers: {'x-tenant': tenant, 'x-namespace': namespace},
    );
    final task = PlatformTask(
      id: taskId,
      tenant: tenant,
      namespace: namespace,
      idempotencyKey: idempotencyKey,
      message: message,
    );
    _idempotency[key] = taskId;
    _tasks[taskId] = task;
    return task;
  }

  Future<Map<String, Object?>?> status({
    required String tenant,
    required String namespace,
    required String taskId,
  }) async {
    if (tenant != config.defaultTenant ||
        namespace != config.defaultNamespace) {
      return null;
    }
    final task = _tasks[taskId];
    if (task == null || task.tenant != tenant || task.namespace != namespace) {
      return null;
    }
    final status = await _stem.getTaskStatus(taskId);
    return status?.toJson();
  }

  Future<Map<String, Object?>?> waitForTask(String taskId) async {
    final result = await _stem.waitForTask<Map<String, Object?>>(
      taskId,
      timeout: const Duration(seconds: 5),
    );
    if (result == null) return null;
    return {
      'taskId': result.taskId,
      'status': result.status.toJson(),
      'value': result.value,
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_started) {
      await _worker.shutdown(mode: WorkerShutdownMode.hard);
    }
    await _stem.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Platform runtime is closed');
    if (!_started) throw StateError('Platform runtime has not started');
  }

  static Future<Object?> _echo(
    TaskInvocationContext context,
    Map<String, Object?> args,
  ) async {
    return {'message': args['message']?.toString() ?? '', 'taskId': context.id};
  }
}

final class PlatformTask {
  const PlatformTask({
    required this.id,
    required this.tenant,
    required this.namespace,
    required this.idempotencyKey,
    required this.message,
  });

  final String id;
  final String tenant;
  final String namespace;
  final String idempotencyKey;
  final String message;
}
