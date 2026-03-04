import '../provider/provider.dart';
import 'event.dart';

/// Event fired when a service provider is registered.
final class ProviderRegisteredEvent extends Event {
  /// The service provider that was registered.
  final ServiceProvider provider;

  /// Creates a new provider registered event.
  ProviderRegisteredEvent(this.provider);
}

/// Event fired when a service provider is booted.
final class ProviderBootedEvent extends Event {
  /// The service provider that was booted.
  final ServiceProvider provider;

  /// Creates a new provider booted event.
  ProviderBootedEvent(this.provider);
}

/// Event fired when a request-scoped container is created.
final class RequestContainerCreatedEvent extends Event {
  /// The unique identifier for the request container.
  final String containerId;

  /// Creates a new request container created event.
  RequestContainerCreatedEvent(this.containerId);
}

/// Event fired when a request-scoped container is disposed.
final class RequestContainerDisposedEvent extends Event {
  /// The unique identifier for the request container.
  final String containerId;

  /// Creates a new request container disposed event.
  RequestContainerDisposedEvent(this.containerId);
}

/// Event fired when an error occurs in the framework.
final class SystemErrorEvent extends Event {
  /// The error that occurred.
  final Object error;

  /// The stack trace associated with the error.
  final StackTrace? stackTrace;

  /// Creates a new system error event.
  SystemErrorEvent(this.error, [this.stackTrace]);
}

/// Event fired when a binding is registered in the container.
final class BindingRegisteredEvent extends Event {
  /// The type that was bound.
  final Type boundType;

  /// Whether the binding is a singleton.
  final bool isSingleton;

  /// Creates a new binding registered event.
  BindingRegisteredEvent(this.boundType, this.isSingleton);
}

/// Event fired when an instance is resolved from the container.
final class InstanceResolvedEvent extends Event {
  /// The type that was resolved.
  final Type resolvedType;

  /// Whether the instance was resolved from a singleton binding.
  final bool fromSingleton;

  /// Creates a new instance resolved event.
  InstanceResolvedEvent(this.resolvedType, this.fromSingleton);
}
