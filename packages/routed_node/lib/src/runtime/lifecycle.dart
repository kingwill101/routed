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
  /// Performs the RoutedNodeLifecycleEvent operation.
  RoutedNodeLifecycleEvent({
    required this.phase,
    required this.info,
    this.requestId,
    this.error,
    this.stackTrace,
  });

  /// The phase value.
  final RoutedNodeLifecyclePhase phase;

  /// The info value.
  final RoutedNodeRuntimeInfo info;

  /// The requestId value.
  final String? requestId;

  /// The error value.
  final Object? error;

  /// The stackTrace value.
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
