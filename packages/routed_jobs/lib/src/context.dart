part of '../routed_jobs.dart';

/// Context available while a job handler is executing.
///
/// The context exposes only Routed abstractions. It can dispatch child jobs,
/// report progress, request a retry, and cooperate with cancellation without
/// coupling application code to a queue vendor or execution engine.
final class JobContext {
  JobContext._({
    required this.id,
    required this.attempt,
    required this.headers,
    required this.meta,
    required this._dispatcher,
    required this._retry,
    required this._heartbeat,
    required this._progress,
    required this._cancellationRequested,
  });

  JobContext._fromStem(
    stem.TaskContext context,
    JobDispatcher dispatcher,
  ) : this._(
        id: context.id,
        attempt: context.attempt,
        headers: Map<String, String>.unmodifiable(context.headers),
        meta: Map<String, Object?>.unmodifiable(context.meta),
        dispatcher: dispatcher,
        retry: (delay) => context.retry(countdown: delay),
        heartbeat: context.heartbeat,
        progress: context.progress,
        cancellationRequested: () =>
            context.cancellation.isCancellationRequested,
      );

  /// Stable logical job ID. It remains unchanged across retries.
  final String id;

  /// Zero-based delivery attempt.
  final int attempt;

  /// Message headers.
  final Map<String, String> headers;

  /// Application metadata.
  final Map<String, Object?> meta;

  final JobDispatcher _dispatcher;
  final Future<void> Function(Duration? delay) _retry;
  final void Function() _heartbeat;
  final Future<void> Function(
    double percentComplete, {
    Map<String, Object?>? data,
  })
  _progress;
  final bool Function() _cancellationRequested;

  /// Dispatches another registered job.
  Future<JobReceipt<TResult>> dispatch<TArgs, TResult>(
    JobDefinition<TArgs, TResult> definition,
    TArgs args, {
    JobDispatchOptions options = const JobDispatchOptions(),
  }) {
    return _dispatcher.dispatch(definition, args, options: options);
  }

  /// Requests a retry of this delivery.
  ///
  /// The request is converted into a retry outcome by [RoutedJobs.process].
  Future<void> retry({Duration? delay}) => _retry(delay);

  /// Notifies the host that this job remains active.
  void heartbeat() => _heartbeat();

  /// Reports progress to the host adapter.
  Future<void> progress(
    double percentComplete, {
    Map<String, Object?>? data,
  }) => _progress(percentComplete, data: data);

  /// Whether cooperative cancellation has been requested.
  bool get cancellationRequested => _cancellationRequested();
}
