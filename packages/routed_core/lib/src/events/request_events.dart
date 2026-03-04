import 'event.dart';

/// Event emitted when a request context is initialised.
base class RequestStartedEvent<TContext> extends Event {
  RequestStartedEvent(this.context);

  /// Context for the current request.
  final TContext context;
}

/// Event emitted after the request pipeline completes.
base class RequestFinishedEvent<TContext> extends Event {
  RequestFinishedEvent(this.context);

  /// Context for the completed request.
  final TContext context;
}
