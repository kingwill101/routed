import 'package:routed_core/routed_core.dart';

import 'runtime.dart';

/// Lifecycle phases emitted by a `routed_node` host.
enum RoutedNodeLifecyclePhase {
  /// A host requested startup.
  bootRequested,

  /// The host is ready to accept requests.
  ready,

  /// A request started.
  requestStarted,

  /// A request completed successfully.
  requestFinished,

  /// A request failed.
  requestFailed,

  /// A host requested shutdown.
  shutdownRequested,

  /// The host stopped accepting requests.
  stopped,
}

/// Host lifecycle event published through Routed's existing [EventManager].
final class RoutedNodeLifecycleEvent extends Event {
  /// Creates a lifecycle event for a host adapter transition.
  RoutedNodeLifecycleEvent({
    required this.phase,
    required this.info,
    this.requestId,
    this.error,
    this.stackTrace,
  });

  /// The lifecycle phase represented by this event.
  final RoutedNodeLifecyclePhase phase;

  /// Runtime metadata for the host that emitted the event.
  final RoutedNodeRuntimeInfo info;

  /// The host request identifier, when one is available.
  final String? requestId;

  /// The failure associated with the event, when [phase] is `requestFailed`.
  final Object? error;

  /// The stack trace associated with [error], when available.
  final StackTrace? stackTrace;
}

/// Publishes a host lifecycle event when the engine has an EventManager.
void publishRoutedNodeLifecycle(Engine engine, RoutedNodeLifecycleEvent event) {
  if (!engine.container.has<EventManager>()) return;
  try {
    engine.container.get<EventManager>().publish(event);
  } on StateError {
    // A host may publish boot events before asynchronous providers finish
    // resolving. Lifecycle publication must never prevent the Worker export
    // from being installed.
  }
}
