import 'dart:async';

import 'package:routed_core/src/container/container.dart';

/// Base class for service providers that register services with the container.
///
/// Service providers are responsible for registering bindings with the
/// container and performing setup and cleanup during the engine lifecycle.
abstract class ServiceProvider {
  /// Registers bindings, instances, and aliases with [container].
  void register(Container container);

  /// Runs after all providers have registered their bindings.
  Future<void> boot(Container container) async {}

  /// Releases resources owned by this provider.
  Future<void> cleanup(Container container) async {}
}

/// Implement on a [ServiceProvider] to declare dependencies by type.
///
/// Providers declaring dependencies will only boot once all dependency types
/// are available in the container.
mixin ProvidesDependencies on ServiceProvider {
  /// Types that must be registered before this provider boots.
  List<Type> get dependencies => const <Type>[];
}

/// Thrown when a provider receives an invalid typed configuration or runtime
/// option.
class ProviderConfigException implements Exception {
  ProviderConfigException(this.message);

  /// Description of the invalid option.
  final String message;

  @override
  String toString() => 'ProviderConfigException: $message';
}
