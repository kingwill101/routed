/// Base class for all events in the system.
///
/// All events should extend this class to ensure proper type safety and
/// event handling throughout the application.
///
/// Example:
/// ```dart
/// class UserCreatedEvent extends Event {
///   final String userId;
///   final String username;
///
///   UserCreatedEvent(this.userId, this.username);
/// }
/// ```
base class Event {
  /// The timestamp when the event was created.
  final DateTime timestamp;

  /// Creates a new event with the current timestamp.
  Event() : timestamp = DateTime.now();
}
