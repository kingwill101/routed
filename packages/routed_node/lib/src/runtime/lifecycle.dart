import 'package:routed_core/routed_core.dart';

import 'runtime.dart';

/// Lifecycle phases emitted by a `routed_node` host.
enum RoutedNodeLifecyclePhase {
  bootRequested,
  ready,
  requestStarted,
  requestFinished,
  requestFailed,
  shutdownRequested,
  stopped,
}

/// Host lifecycle event published through Routed's existing [EventManager].
final class RoutedNodeLifecycleEvent extends Event {
  RoutedNodeLifecycleEvent({
    required this.phase,
    required this.info,
    this.requestId,
    this.error,
    this.stackTrace,
  });

  final RoutedNodeLifecyclePhase phase;
  final RoutedNodeRuntimeInfo info;
  final String? requestId;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Publishes a host lifecycle event when the engine has an EventManager.
void publishRoutedNodeLifecycle(Engine engine, RoutedNodeLifecycleEvent event) {
  if (engine.container.has<EventManager>()) {
    engine.container.get<EventManager>().publish(event);
  }
}
