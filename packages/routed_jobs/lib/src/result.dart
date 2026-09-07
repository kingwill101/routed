part of '../routed_jobs.dart';

/// Processing states returned to a host queue adapter.
enum JobProcessState {
  /// The handler completed successfully; acknowledge the delivery.
  succeeded,

  /// The message should be delivered again after [JobProcessResult.retryAfter].
  retry,

  /// The handler failed terminally; send it to failed-job handling.
  failed,

  /// The message was invalid or unregistered.
  rejected,

  /// The message was cancelled or expired.
  cancelled,

  /// A duplicate terminal delivery was skipped.
  skipped,
}

/// Portable reasons for rejecting a job before handler execution.
enum JobRejectionReason {
  /// No definition is registered for the message name.
  unregisteredJob,

  /// The message signature could not be verified.
  invalidSignature,

  /// The message payload could not be decoded.
  invalidPayload,
}

/// Portable reasons for cancellation.
enum JobCancellationReason {
  /// The message expired before it could execute.
  expired,

  /// The runtime or handler cooperatively cancelled the message.
  cancelled,
}

/// Result of processing one queue message.
final class JobProcessResult {
  const JobProcessResult._({
    required this.message,
    required this.state,
    this.value,
    this.retryMessage,
    this.retryAfter,
    this.error,
    this.stackTrace,
    this.rejectionReason,
    this.cancellationReason,
    this.retryExhausted = false,
  });

  /// Creates a successful result.
  const JobProcessResult.succeeded(JobMessage message, {Object? value})
    : this._(message: message, state: JobProcessState.succeeded, value: value);

  /// Creates a retry result.
  const JobProcessResult.retry(
    JobMessage message, {
    required JobMessage retryMessage,
    required Duration retryAfter,
    Object? error,
    StackTrace? stackTrace,
  }) : this._(
         message: message,
         state: JobProcessState.retry,
         retryMessage: retryMessage,
         retryAfter: retryAfter,
         error: error,
         stackTrace: stackTrace,
       );

  /// Creates a terminal failure result.
  const JobProcessResult.failed(
    JobMessage message, {
    required Object error,
    StackTrace? stackTrace,
    bool retryExhausted = false,
  }) : this._(
         message: message,
         state: JobProcessState.failed,
         error: error,
         stackTrace: stackTrace,
         retryExhausted: retryExhausted,
       );

  /// Creates a rejected result.
  const JobProcessResult.rejected(
    JobMessage message, {
    required JobRejectionReason reason,
    Object? error,
    StackTrace? stackTrace,
  }) : this._(
         message: message,
         state: JobProcessState.rejected,
         rejectionReason: reason,
         error: error,
         stackTrace: stackTrace,
       );

  /// Creates a cancellation result.
  const JobProcessResult.cancelled(
    JobMessage message, {
    required JobCancellationReason reason,
    Object? error,
  }) : this._(
         message: message,
         state: JobProcessState.cancelled,
         cancellationReason: reason,
         error: error,
       );

  /// Creates a duplicate-delivery result.
  const JobProcessResult.skipped(JobMessage message)
    : this._(message: message, state: JobProcessState.skipped);

  /// Original message processed by the consumer.
  final JobMessage message;

  /// Semantic processing state.
  final JobProcessState state;

  /// Handler return value for successful processing.
  final Object? value;

  /// Message to republish for a retry, when [state] is [JobProcessState.retry].
  final JobMessage? retryMessage;

  /// Delay before republishing [retryMessage].
  final Duration? retryAfter;

  /// Failure or rejection error.
  final Object? error;

  /// Associated stack trace, when one exists.
  final StackTrace? stackTrace;

  /// Rejection reason, when [state] is rejected.
  final JobRejectionReason? rejectionReason;

  /// Cancellation reason, when [state] is cancelled.
  final JobCancellationReason? cancellationReason;

  /// Whether the configured retry budget was exhausted.
  final bool retryExhausted;

  /// Whether the host can acknowledge this delivery as complete.
  bool get isTerminal => switch (state) {
    JobProcessState.succeeded ||
    JobProcessState.failed ||
    JobProcessState.rejected ||
    JobProcessState.cancelled ||
    JobProcessState.skipped => true,
    JobProcessState.retry => false,
  };
}

/// Receipt returned after a job is published.
final class JobReceipt<TResult> {
  /// Creates a job receipt.
  const JobReceipt({required this.id, required this.name});

  /// Stable logical job ID.
  final String id;

  /// Registered job name.
  final String name;
}
