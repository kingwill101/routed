import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/events/event.dart';

/// Event emitted when a request context is initialised.
final class RequestStartedEvent extends Event {
  /// Creates an event for [context].
  RequestStartedEvent(this.context);

  /// Context for the current request.
  final EngineContext context;
}

/// Event emitted after the request pipeline completes.
final class RequestFinishedEvent extends Event {
  /// Creates an event for the completed [context].
  RequestFinishedEvent(this.context);

  /// Context for the completed request.
  final EngineContext context;
}
