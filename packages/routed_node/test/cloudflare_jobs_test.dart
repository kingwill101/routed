import 'package:routed_jobs/routed_jobs.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:test/test.dart';

void main() {
  test('Cloudflare job batch acknowledges terminal outcomes', () async {
    final calls = <String>[];
    final batch = _batch([
      _delivery({
        'id': 'job-1',
        'name': 'known',
        'args': <String, Object?>{},
      }, calls),
      _delivery({
        'id': 'job-2',
        'name': 'unknown',
        'args': <String, Object?>{},
      }, calls),
      _delivery('not-a-job', calls),
    ]);
    final known = JobDefinition<void, String>(
      name: 'known',
      encode: (_) => const {},
      decode: (_) {},
      handle: (_, _) async => 'ok',
    );
    final jobs = RoutedJobs(queue: InMemoryJobQueue(), definitions: [known]);

    await processCloudflareJobBatch(batch, jobs);

    expect(calls, ['ack', 'ack', 'ack']);
    await jobs.close();
  });

  test('Cloudflare job batch retries portable retry outcomes', () async {
    final calls = <String>[];
    final batch = _batch([
      _delivery({
        'id': 'job-1',
        'name': 'retry',
        'args': <String, Object?>{},
        'maxAttempts': 3,
      }, calls),
    ]);
    final definition = JobDefinition<void, void>(
      name: 'retry',
      encode: (_) => const {},
      decode: (_) {},
      options: const JobOptions(maxAttempts: 3),
      handle: (context, _) => context.retry(delay: const Duration(seconds: 4)),
    );
    final jobs = RoutedJobs(
      queue: InMemoryJobQueue(),
      definitions: [definition],
    );

    await processCloudflareJobBatch(batch, jobs);

    expect(calls, ['retry:4']);
    await jobs.close();
  });

  test('Cloudflare event exports fail clearly on the VM', () {
    expect(
      () => defineCloudflareQueueExport((_, _, _) {}),
      throwsUnsupportedError,
    );
    expect(
      () => defineCloudflareScheduledExport((_, _, _) {}),
      throwsUnsupportedError,
    );
  });
}

CloudflareQueueBatch _batch(List<CloudflareQueueDelivery> messages) {
  return CloudflareQueueBatch(
    queue: 'jobs',
    messages: messages,
    acknowledgeAll: () {},
    retryAllHandler: (_) {},
  );
}

CloudflareQueueDelivery _delivery(Object body, List<String> calls) {
  return CloudflareQueueDelivery(
    id: 'delivery-${calls.length}',
    timestamp: DateTime.utc(2026, 1, 1),
    attempts: 1,
    body: body,
    acknowledge: () => calls.add('ack'),
    retryHandler: (delay) => calls.add('retry:${delay?.inSeconds ?? 0}'),
  );
}
