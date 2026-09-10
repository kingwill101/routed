part of '../routed_jobs.dart';

/// Minimal queue transport required by [RoutedJobs].
///
/// The transport receives an immutable [JobMessage]. Consumer runtimes do not
/// need to expose a polling API: they can pass pushed messages to
/// [JobConsumer.process] and map the returned [JobProcessResult] to their own
/// acknowledgement, retry, and dead-letter operations.
// ignore: one_member_abstracts
abstract interface class JobQueue {
  /// Publishes [message] to its queue.
  Future<void> publish(JobMessage message);
}

/// Simple in-memory queue useful for local development and tests.
final class InMemoryJobQueue implements JobQueue {
  /// Messages published to this queue, in publication order.
  final List<JobMessage> messages = [];

  @override
  Future<void> publish(JobMessage message) async => messages.add(message);
}

/// Public dispatch surface used by HTTP handlers, services, and schedules.
// ignore: one_member_abstracts
abstract interface class JobDispatcher {
  /// Dispatches [args] for a registered [definition].
  Future<JobReceipt<TResult>> dispatch<TArgs, TResult>(
    JobDefinition<TArgs, TResult> definition,
    TArgs args, {
    JobDispatchOptions options = const JobDispatchOptions(),
  });
}

/// Public processing surface used by queue consumers and event adapters.
// ignore: one_member_abstracts
abstract interface class JobConsumer {
  /// Processes one message and returns a transport-neutral outcome.
  Future<JobProcessResult> process(
    JobMessage message, {
    int? deliveryAttempt,
  });
}
