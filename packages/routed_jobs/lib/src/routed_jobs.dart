part of '../routed_jobs.dart';

/// Routed's jobs facade and portable consumer adapter.
final class RoutedJobs implements JobDispatcher, JobConsumer {
  /// Creates a jobs facade backed by [queue].
  ///
  /// Every definition must be registered before it is dispatched or consumed.
  /// Registrations are manual by design, so this API works without
  /// `build_runner`.
  RoutedJobs({
    required JobQueue queue,
    Iterable<JobDefinitionBase> definitions = const [],
  }) : _registry = stem.InMemoryTaskRegistry() {
    _publisher = _RoutedTaskPublisher(queue);
    _stem = stem.Stem.withPublisher(
      publisher: _publisher,
      registry: _registry,
    );
    _processor = stem.TaskProcessor(registry: _registry);
    definitions.forEach(register);
  }

  final stem.InMemoryTaskRegistry _registry;
  late final _RoutedTaskPublisher _publisher;
  late final stem.Stem _stem;
  late final stem.TaskProcessor _processor;
  final Map<String, JobDefinitionBase> _definitions = {};

  /// Definitions currently registered with this facade.
  Iterable<JobDefinitionBase> get definitions =>
      List<JobDefinitionBase>.unmodifiable(_definitions.values);

  /// Registers a definition for dispatch and processing.
  void register(JobDefinitionBase definition, {bool overrideExisting = false}) {
    definition.options.validate(definition.name);
    if (!overrideExisting && _definitions.containsKey(definition.name)) {
      throw ArgumentError(
        'Job definition "${definition.name}" is already registered.',
      );
    }
    final handler = _StemJobHandler(definition, this);
    _registry.register(handler, overrideExisting: overrideExisting);
    _definitions[definition.name] = definition;
  }

  /// Dispatches a typed job to the configured queue.
  @override
  Future<JobReceipt<TResult>> dispatch<TArgs, TResult>(
    JobDefinition<TArgs, TResult> definition,
    TArgs args, {
    JobDispatchOptions options = const JobDispatchOptions(),
  }) async {
    options.validate();
    final registered = _definitions[definition.name];
    if (!identical(registered, definition)) {
      throw ArgumentError(
        'Job "${definition.name}" must be registered before dispatch.',
      );
    }

    final definitionOptions = definition.options;
    final queue = options.queue?.trim() ?? definitionOptions.queue.trim();
    final notBefore = options.delay == null
        ? null
        : DateTime.now().toUtc().add(options.delay!);
    final taskId = await _stem.enqueue(
      definition.name,
      args: definition.encodeUntyped(args),
      headers: Map<String, String>.from(options.headers),
      options: _toStemOptions(definitionOptions, queue: queue),
      notBefore: notBefore,
      meta: Map<String, Object?>.from(options.meta),
      enqueueOptions: stem.TaskEnqueueOptions(
        taskId: options.idempotencyKey,
        priority: options.priority,
      ),
    );
    return JobReceipt<TResult>(id: taskId, name: definition.name);
  }

  /// Processes one host-delivered message through the portable runtime.
  @override
  Future<JobProcessResult> process(
    JobMessage message, {
    int? deliveryAttempt,
  }) async {
    final envelopeJson = message.toJson()
      ..['maxRetries'] = message.maxAttempts - 1
      ..remove('maxAttempts');
    final outcome = await _processor.process(
      stem.Envelope.fromJson(envelopeJson),
      deliveryAttempt: deliveryAttempt,
    );
    final effectiveMessage = JobMessage.fromJson(outcome.envelope.toJson());
    return switch (outcome) {
      stem.TaskProcessSuccess(:final value) => JobProcessResult.succeeded(
        effectiveMessage,
        value: value,
      ),
      stem.TaskProcessRetry(
        :final nextEnvelope,
        :final delay,
        :final error,
        :final stackTrace,
      ) =>
        JobProcessResult.retry(
          effectiveMessage,
          retryMessage: JobMessage.fromJson(nextEnvelope.toJson()),
          retryAfter: delay,
          error: error,
          stackTrace: stackTrace,
        ),
      stem.TaskProcessFailure(
        :final error,
        :final stackTrace,
        :final retryExhausted,
      ) =>
        JobProcessResult.failed(
          effectiveMessage,
          error: error,
          stackTrace: stackTrace,
          retryExhausted: retryExhausted,
        ),
      stem.TaskProcessRejected(
        :final reason,
        :final error,
        :final stackTrace,
      ) =>
        JobProcessResult.rejected(
          effectiveMessage,
          reason: _rejectionReason(reason),
          error: error,
          stackTrace: stackTrace,
        ),
      stem.TaskProcessCancelled(:final reason, :final error) =>
        JobProcessResult.cancelled(
          effectiveMessage,
          reason: _cancellationReason(reason),
          error: error,
        ),
      stem.TaskProcessSkipped() => JobProcessResult.skipped(effectiveMessage),
    };
  }

  /// Releases internal runtime resources.
  ///
  /// The queue adapter remains owned by the caller and is not closed.
  Future<void> close() => _stem.close();

  stem.TaskOptions _toStemOptions(
    JobOptions options, {
    required String queue,
  }) {
    final policy = options.retryPolicy;
    return stem.TaskOptions(
      queue: queue,
      maxRetries: options.maxAttempts - 1,
      softTimeLimit: options.softTimeout,
      hardTimeLimit: options.timeout,
      priority: options.priority,
      visibilityTimeout: options.visibilityTimeout,
      retryPolicy: policy == null
          ? null
          : stem.TaskRetryPolicy(
              backoff: policy.backoff,
              backoffMax: policy.backoffMax,
              jitter: policy.jitter,
              defaultDelay: policy.defaultDelay,
            ),
    );
  }

  static JobRejectionReason _rejectionReason(stem.TaskRejectionReason reason) {
    return switch (reason) {
      stem.TaskRejectionReason.unregisteredTask =>
        JobRejectionReason.unregisteredJob,
      stem.TaskRejectionReason.invalidSignature =>
        JobRejectionReason.invalidSignature,
      stem.TaskRejectionReason.invalidPayload =>
        JobRejectionReason.invalidPayload,
    };
  }

  static JobCancellationReason _cancellationReason(
    stem.TaskCancellationReason reason,
  ) {
    return switch (reason) {
      stem.TaskCancellationReason.expired => JobCancellationReason.expired,
      stem.TaskCancellationReason.cancelled => JobCancellationReason.cancelled,
    };
  }
}

final class _RoutedTaskPublisher implements stem.TaskPublisher {
  _RoutedTaskPublisher(this.queue);

  final JobQueue queue;

  @override
  Future<void> publish(
    stem.Envelope envelope, {
    stem.RoutingInfo? routing,
  }) {
    return queue.publish(JobMessage.fromJson(envelope.toJson()));
  }
}

final class _StemJobHandler extends stem.TaskHandler<Object?> {
  _StemJobHandler(this.definition, this.jobs);

  final JobDefinitionBase definition;
  final RoutedJobs jobs;

  @override
  String get name => definition.name;

  @override
  stem.TaskOptions get options => jobs._toStemOptions(
    definition.options,
    queue: definition.options.queue,
  );

  @override
  Future<Object?> call(
    stem.TaskContext context,
    Map<String, Object?> args,
  ) {
    return definition.invoke(JobContext._fromStem(context, jobs), args);
  }
}
