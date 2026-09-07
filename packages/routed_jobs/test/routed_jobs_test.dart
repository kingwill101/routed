import 'package:routed_core/routed_core.dart';
import 'package:routed_jobs/routed_jobs.dart';
import 'package:test/test.dart';

void main() {
  group('RoutedJobs', () {
    test('dispatches a durable message without exposing Stem', () async {
      final queue = RecordingQueue();
      final job = JobDefinition<String, String>(
        name: 'mail.welcome',
        encode: (email) => {'email': email},
        decode: (payload) => payload['email']! as String,
        options: const JobOptions(maxAttempts: 3),
        handle: (_, email) async => email,
      );
      final jobs = RoutedJobs(queue: queue, definitions: [job]);

      final receipt = await jobs.dispatch(
        job,
        'person@example.com',
        options: const JobDispatchOptions(
          queue: 'mail',
          delay: Duration(seconds: 5),
          idempotencyKey: 'welcome-1',
          headers: {'tenant': 'acme'},
          meta: {'source': 'signup'},
        ),
      );

      expect(receipt.id, 'welcome-1');
      expect(queue.messages, hasLength(1));
      final message = queue.messages.single;
      expect(message.id, receipt.id);
      expect(message.name, 'mail.welcome');
      expect(message.args, {'email': 'person@example.com'});
      expect(message.queue, 'mail');
      expect(message.maxAttempts, 3);
      expect(message.headers, {'tenant': 'acme'});
      expect(message.meta['source'], 'signup');
      expect(message.toJson()['maxAttempts'], 3);
      expect(message.toJson(), isNot(contains('maxRetries')));
      expect(message.notBefore, isNotNull);
    });

    test('processes a job and exposes the portable context', () async {
      final queue = RecordingQueue();
      late JobContext receivedContext;
      final job = JobDefinition<int, int>(
        name: 'numbers.double',
        encode: (value) => {'value': value},
        decode: (payload) => payload['value']! as int,
        handle: (context, value) async {
          receivedContext = context;
          return value * 2;
        },
      );
      final jobs = RoutedJobs(queue: queue, definitions: [job]);
      await jobs.dispatch(job, 21);

      final result = await jobs.process(queue.messages.single);

      expect(result.state, JobProcessState.succeeded);
      expect(result.value, 42);
      expect(receivedContext.id, queue.messages.single.id);
      expect(receivedContext.attempt, 0);
      expect(receivedContext.cancellationRequested, isFalse);
    });

    test('turns an explicit retry into a republishable message', () async {
      final queue = RecordingQueue();
      final job = JobDefinition<void, void>(
        name: 'billing.sync',
        encode: (_) => const {},
        decode: (_) {},
        options: const JobOptions(maxAttempts: 2),
        handle: (context, _) =>
            context.retry(delay: const Duration(seconds: 2)),
      );
      final jobs = RoutedJobs(queue: queue, definitions: [job]);
      await jobs.dispatch(job, null);

      final result = await jobs.process(queue.messages.single);

      expect(result.state, JobProcessState.retry);
      expect(result.retryAfter, const Duration(seconds: 2));
      expect(result.retryMessage, isNotNull);
      expect(result.retryMessage!.id, queue.messages.single.id);
      expect(result.retryMessage!.attempt, 1);
    });

    test('applies the configured attempt budget to failures', () async {
      final queue = RecordingQueue();
      final job = JobDefinition<void, void>(
        name: 'billing.fail',
        encode: (_) => const <String, Object?>{},
        decode: (_) {},
        options: const JobOptions(maxAttempts: 2),
        handle: (_, _) => throw StateError('temporary'),
      );
      final jobs = RoutedJobs(queue: queue, definitions: [job]);
      await jobs.dispatch(job, null);

      final retry = await jobs.process(queue.messages.single);
      final terminal = await jobs.process(retry.retryMessage!);

      expect(retry.state, JobProcessState.retry);
      expect(terminal.state, JobProcessState.failed);
      expect(terminal.retryExhausted, isTrue);
    });

    test('rejects a message for an unregistered job', () async {
      final jobs = RoutedJobs(queue: RecordingQueue());
      final message = JobMessage.fromJson({
        'id': 'job-1',
        'name': 'missing',
        'args': const <String, Object?>{},
      });

      final result = await jobs.process(message);

      expect(result.state, JobProcessState.rejected);
      expect(result.rejectionReason, JobRejectionReason.unregisteredJob);
    });
  });

  test('provider registers dispatcher and consumer instances', () {
    final queue = RecordingQueue();
    final provider = RoutedJobsProvider(JobsConfig(queue: queue));
    final container = Container();

    provider.register(container);

    expect(container.get<JobDispatcher>(), isA<RoutedJobs>());
    expect(container.get<JobConsumer>(), same(container.get<JobDispatcher>()));
  });
}

final class RecordingQueue implements JobQueue {
  final List<JobMessage> messages = [];

  @override
  Future<void> publish(JobMessage message) async => messages.add(message);
}
