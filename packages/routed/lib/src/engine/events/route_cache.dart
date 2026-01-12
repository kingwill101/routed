import 'package:routed/src/events/event.dart';

/// Event emitted when route cache should be rebuilt.
final class RouteCacheInvalidatedEvent extends Event {
  RouteCacheInvalidatedEvent() : super();
}
