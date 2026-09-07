import 'package:routed_jobs/routed_jobs.dart';

import 'cloudflare_bindings_stub.dart'
    if (dart.library.js_interop) 'cloudflare_bindings_js.dart'
    as cloudflare_bindings;
import 'cloudflare_types.dart';

/// Publishes Routed jobs to one Cloudflare Queue binding.
///
/// Cloudflare delivers queue messages to a Worker queue handler. That handler
/// should decode the body as a [JobMessage], call [JobConsumer.process], and
/// map the result to Cloudflare's per-message acknowledgement and retry API.
/// This adapter is producer-only; it does not invent a polling worker model
/// for Workers.
final class CloudflareJobQueue implements JobQueue {
  /// Creates a producer for [queue].
  CloudflareJobQueue(this.queue);

  /// Cloudflare Queue producer binding.
  final CloudflareQueue queue;

  @override
  Future<void> publish(JobMessage message) async {
    await queue.send(
      message.toJson(),
      contentType: CloudflareQueueContentType.json,
      delaySeconds: _delaySeconds(message.notBefore),
    );
  }

  static int? _delaySeconds(DateTime? notBefore) {
    if (notBefore == null) return null;
    final milliseconds = notBefore.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds + 999) ~/ 1000;
  }
}

/// Runs a Routed [consumer] against one Cloudflare Queue delivery batch.
///
/// Terminal outcomes are acknowledged. A retry outcome uses Cloudflare's
/// native per-message retry operation, preserving the platform's delivery
/// attempt counter. Unexpected consumer errors are retried as well, so a
/// transient Worker or storage failure cannot be mistaken for successful
/// processing.
Future<void> processCloudflareJobBatch(
  CloudflareQueueBatch batch,
  JobConsumer consumer,
) async {
  for (final delivery in batch.messages) {
    try {
      final body = delivery.body;
      if (body is! Map) {
        delivery.ack();
        continue;
      }
      final payload = <String, Object?>{};
      for (final entry in body.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Cloudflare job payload keys must be strings',
          );
        }
        payload[entry.key as String] = entry.value;
      }
      final message = JobMessage.fromJson(payload);
      final result = await consumer.process(
        message,
        // Cloudflare's attempts counter starts at one, while the portable
        // jobs contract (and Stem's internal envelope) is zero-based.
        deliveryAttempt: delivery.attempts < 1 ? 0 : delivery.attempts - 1,
      );
      if (result.state == JobProcessState.retry) {
        delivery.retry(delay: result.retryAfter);
      } else {
        delivery.ack();
      }
    } on Object {
      delivery.retry();
    }
  }
}

/// Installs the standard Cloudflare Queue export for Routed jobs.
///
/// The factory is evaluated lazily once per Worker isolate. It may create an
/// environment-backed [RoutedJobs] instance from D1, KV, or other bindings.
void defineCloudflareJobsQueueExportFactoryWithEnvironmentAsync(
  Future<JobConsumer> Function(CloudflareEnvironment environment) factory,
) {
  Future<JobConsumer>? consumerFuture;
  cloudflare_bindings.defineCloudflareQueueExport((
    batch,
    environment,
    _,
  ) {
    consumerFuture ??= factory(environment);
    return consumerFuture!.then((consumer) {
      return processCloudflareJobBatch(batch, consumer);
    });
  });
}
