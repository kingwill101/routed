import 'package:routed_core/src/events/event.dart';

/// Event emitted when route cache should be rebuilt.
final class RouteCacheInvalidatedEvent extends Event {
  RouteCacheInvalidatedEvent() : super();
}
