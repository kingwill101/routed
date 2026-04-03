import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart' show EngineRoute;
import 'package:routed/src/engine/events/request.dart';
import 'package:routed/src/engine/events/route.dart';
import 'package:routed_core/routed_core.dart' as core;

export 'package:routed_core/src/events/signals.dart'
    show
        Signal,
        SignalHandlerEntry,
        SignalHandlerKey,
        SignalSenderMatcher,
        SignalSubscription,
        UnhandledSignalError;

typedef RequestSignalSender =
    core.RequestSignalSender<EngineContext, EngineRoute>;

typedef RequestSignals =
    core.RequestSignals<
      EngineContext,
      EngineRoute,
      RequestStartedEvent,
      RequestFinishedEvent,
      RouteMatchedEvent,
      RoutingErrorEvent,
      AfterRoutingEvent
    >;

typedef SignalHub =
    core.SignalHub<
      EngineContext,
      EngineRoute,
      RequestStartedEvent,
      RequestFinishedEvent,
      RouteMatchedEvent,
      RoutingErrorEvent,
      AfterRoutingEvent
    >;
