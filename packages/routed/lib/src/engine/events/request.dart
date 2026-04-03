import 'package:routed/src/context/context.dart';
import 'package:routed_core/routed_core.dart' as core;

/// Event emitted when a request context is initialised.
final class RequestStartedEvent
    extends core.RequestStartedEvent<EngineContext> {
  RequestStartedEvent(super.context);
}

/// Event emitted after the request pipeline completes.
final class RequestFinishedEvent
    extends core.RequestFinishedEvent<EngineContext> {
  RequestFinishedEvent(super.context);
}
