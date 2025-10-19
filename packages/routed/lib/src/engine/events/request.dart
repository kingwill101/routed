import 'package:routed/src/context/context.dart';
import 'package:routed/src/events/event.dart';

/// Event emitted when a request context is initialised.
final class RequestStartedEvent extends Event {
  RequestStartedEvent(this.context);

  /// Context for the current request.
  final EngineContext context;
}

/// Event emitted after the request pipeline completes.
final class RequestFinishedEvent extends Event {
  RequestFinishedEvent(this.context);

  /// Context for the completed request.
  final EngineContext context;
}
