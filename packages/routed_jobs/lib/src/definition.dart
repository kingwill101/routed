part of '../routed_jobs.dart';

/// Handler used by a [JobDefinition].
typedef JobHandler<TArgs, TResult> =
    FutureOr<TResult> Function(
      JobContext context,
      TArgs args,
    );

/// Retry behavior applied when a job fails without explicitly requesting a
/// retry.
final class JobRetryPolicy {
  /// Creates a retry policy.
  const JobRetryPolicy({
    this.backoff = false,
    this.backoffMax,
    this.jitter = true,
    this.defaultDelay = Duration.zero,
  });

  /// Whether retry delays should grow exponentially.
  final bool backoff;

  /// Maximum computed retry delay.
  final Duration? backoffMax;

  /// Whether computed backoff may include jitter.
  final bool jitter;

  /// Delay used when backoff is disabled.
  final Duration defaultDelay;
}

/// Options attached to a job definition.
///
/// These options are portable defaults. A host adapter remains responsible
/// for mapping attempts and terminal failures to its own queue semantics.
final class JobOptions {
  /// Creates options for a job definition.
  const JobOptions({
    this.queue = 'default',
    this.maxAttempts = 1,
    this.timeout,
    this.softTimeout,
    this.priority = 0,
    this.visibilityTimeout,
    this.retryPolicy,
  });

  /// Queue selected when dispatch does not override it.
  final String queue;

  /// Maximum number of deliveries, including the first attempt.
  final int maxAttempts;

  /// Hard execution timeout.
  final Duration? timeout;

  /// Soft execution timeout.
  final Duration? softTimeout;

  /// Queue priority, when supported by the adapter.
  final int priority;

  /// Lease visibility timeout, when supported by the adapter.
  final Duration? visibilityTimeout;

  /// Failure retry policy.
  final JobRetryPolicy? retryPolicy;

  /// Validates these options for [jobName].
  void validate(String jobName) {
    if (jobName.trim().isEmpty) {
      throw ArgumentError.value(jobName, 'name', 'Job name must not be empty');
    }
    if (queue.trim().isEmpty) {
      throw ArgumentError.value(
        queue,
        'queue',
        'Job queue must not be empty',
      );
    }
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Job maxAttempts must be at least 1',
      );
    }
    if (priority < 0) {
      throw ArgumentError.value(
        priority,
        'priority',
        'Job priority must not be negative',
      );
    }
  }
}

/// Dispatch-time overrides for a job.
final class JobDispatchOptions {
  /// Creates dispatch options.
  const JobDispatchOptions({
    this.queue,
    this.delay,
    this.idempotencyKey,
    this.priority,
    this.headers = const {},
    this.meta = const {},
  });

  /// Optional queue override.
  final String? queue;

  /// Delay before the first delivery.
  final Duration? delay;

  /// Stable logical ID for idempotent producer retries.
  final String? idempotencyKey;

  /// Optional priority override.
  final int? priority;

  /// Transport headers.
  final Map<String, String> headers;

  /// Application metadata.
  final Map<String, Object?> meta;

  /// Validates these dispatch overrides.
  void validate() {
    if (queue != null && queue!.trim().isEmpty) {
      throw ArgumentError.value(
        queue,
        'queue',
        'Dispatch queue must not be empty',
      );
    }
    if (idempotencyKey != null && idempotencyKey!.trim().isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'Idempotency key must not be empty',
      );
    }
    if (priority != null && priority! < 0) {
      throw ArgumentError.value(
        priority,
        'priority',
        'Dispatch priority must not be negative',
      );
    }
  }
}

/// Untyped registration surface used by [RoutedJobs] for heterogeneous jobs.
abstract interface class JobDefinitionBase {
  /// The stable transport name for the job.
  String get name;

  /// Default job options.
  JobOptions get options;

  /// Whether the definition can encode the given typed arguments.
  Map<String, Object?> encodeUntyped(Object? args);

  /// Invokes the typed job after decoding its durable argument map.
  Future<Object?> invoke(JobContext context, Map<String, Object?> args);
}

/// A manually registered, strongly typed job definition.
///
/// This is intentionally codegen-free. Applications can keep definitions in
/// ordinary Dart files and register them with [RoutedJobsProvider].
final class JobDefinition<TArgs, TResult> implements JobDefinitionBase {
  /// Creates a typed job definition.
  const JobDefinition({
    required this.name,
    required this.encode,
    required this.decode,
    required this.handle,
    this.options = const JobOptions(),
  });

  @override
  final String name;

  /// Encodes typed arguments into a durable JSON-compatible map.
  final Map<String, Object?> Function(TArgs args) encode;

  /// Decodes the durable map received by a consumer.
  final TArgs Function(Map<String, Object?> payload) decode;

  /// Runs the application job.
  final JobHandler<TArgs, TResult> handle;

  @override
  final JobOptions options;

  @override
  Map<String, Object?> encodeUntyped(Object? args) => encode(args as TArgs);

  @override
  Future<Object?> invoke(JobContext context, Map<String, Object?> args) async {
    return handle(context, decode(args));
  }
}
