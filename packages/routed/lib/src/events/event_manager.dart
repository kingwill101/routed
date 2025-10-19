import 'dart:async';

import 'package:event_bus/event_bus.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/events/event.dart';

/// Manages event bus functionality for the application.
///
/// The EventManager provides a centralized way to publish and subscribe to events
/// using the event bus pattern. It supports:
/// - Publishing events to subscribers
/// - Subscribing to specific event types
/// - Automatic event type inference
/// - Event filtering and transformation
///
/// Example:
/// ```dart
/// final eventManager = EventManager();
///
/// // Subscribe to UserCreatedEvent
/// eventManager.on<UserCreatedEvent>().listen((event) {
///   print('User created: ${event.userId}');
/// });
///
/// // Publish an event
/// eventManager.publish(UserCreatedEvent('123'));
/// ```
class EventManager implements Disposable {
  /// The underlying event bus instance.
  final EventBus _eventBus;
  bool _closed = false;

  /// Creates a new event manager with an optional custom event bus.
  ///
  /// If no event bus is provided, a new one will be created.
  EventManager([EventBus? eventBus]) : _eventBus = eventBus ?? EventBus();

  /// Publishes an event to all subscribers.
  ///
  /// The event will be delivered to all subscribers that are listening
  /// for this specific event type.
  ///
  /// Example:
  /// ```dart
  /// eventManager.publish(UserLoggedInEvent(userId: '123'));
  /// ```
  void publish<T extends Event>(T event) {
    if (_closed) {
      // Silently ignore events after closing
      return;
    }
    _eventBus.fire(event);
  }

  /// Creates a stream of events of type [T].
  ///
  /// Returns a stream that will emit all events of type [T] that are
  /// published through this event manager.
  ///
  /// Example:
  /// ```dart
  /// eventManager.on<UserLoggedOutEvent>().listen((event) {
  ///   // Handle user logout
  /// });
  /// ```
  Stream<T> on<T extends Event>() {
    return _eventBus.on<T>();
  }

  StreamSubscription<T> listen<T extends Event>(void Function(T event) onData) {
    return _eventBus.on<T>().listen(onData);
  }

  /// Destroys the event manager and cleans up resources.
  ///
  /// This should be called when the event manager is no longer needed
  /// to prevent memory leaks.
  void destroy() {
    _closed = true;
    _eventBus.destroy();
  }

  @override
  Future<void> dispose() async {
    destroy();
  }
}
