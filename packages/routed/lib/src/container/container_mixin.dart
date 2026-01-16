import 'dart:io';

import 'package:routed/src/config/config.dart';
import 'package:routed/src/config/registry.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/engine/providers/request.dart'
    show RequestServiceProvider;

import '../provider/provider.dart';

/// A mixin that adds container functionality to the Engine class.
///
/// The ContainerMixin provides dependency injection capabilities to the Engine,
/// managing service providers and request-scoped containers. It handles:
/// - Service provider registration and lifecycle
/// - Request-scoped container creation and cleanup
/// - Dependency resolution
///
/// Example:
/// ```dart
/// class Engine with ContainerMixin {
///   void setup() {
///     registerProvider(CoreServiceProvider());
///     await bootProviders();
///   }
///
///   Future<void> handleRequest(HttpRequest request) async {
///     final container = createRequestContainer(request, request.response);
///     try {
///       // Handle request using container...
///     } finally {
///       await cleanupRequestContainer(container);
///     }
///   }
/// }
/// ```
mixin ContainerMixin {
  /// The main service container instance.
  ///
  /// This container holds application-wide services and serves as the parent
  /// for request-scoped containers.
  final Container _container = Container();

  /// List of registered service providers.
  ///
  /// These providers are responsible for registering and managing services
  /// in the container.
  final List<ServiceProvider> _providers = [];

  final ConfigRegistry _configRegistry = ConfigRegistry();
  bool _configRegistryBound = false;

  /// Whether the service providers have been booted.
  ///
  /// Used to ensure providers are only booted once.
  bool _booted = false;

  /// Gets the main service container instance.
  ///
  /// This container holds application-wide services and can be used
  /// to resolve dependencies outside of request handling.
  Container get container => _container;

  /// Registers a service provider with the container.
  ///
  /// The provider's [register] method is called immediately, but its [boot]
  /// method is deferred until [bootProviders] is called.
  ///
  /// Example:
  /// ```dart
  /// registerProvider(CoreServiceProvider(engine));
  /// ```
  void registerProvider(ServiceProvider provider) {
    _ensureConfigRegistryRegistered();
    if (provider is ProvidesDefaultConfig) {
      final defaults = provider.defaultConfig.snapshot();
      _configRegistry.register(
        defaults.values,
        source: provider.configSource,
        docs: defaults.docs,
        schemas: defaults.schemas,
      );
    }
    _providers.add(provider);
    provider.register(_container);
    if (_booted) {
      provider.boot(_container);
    }
  }

  /// Boots all registered service providers.
  ///
  /// This method:
  /// 1. Checks if providers have already been booted
  /// 2. If not, calls each provider's [boot] method in registration order
  /// 3. Marks providers as booted
  ///
  /// This method is idempotent - calling it multiple times will only boot
  /// the providers once.
  Future<void> bootProviders() async {
    if (_booted) {
      return;
    }
    for (final provider in _providers) {
      await provider.boot(_container);
    }

    _booted = true;
  }

  /// Creates a new container scoped to a specific HTTP request.
  ///
  /// The new container:
  /// - Inherits bindings from the main container
  /// - Has request-specific services registered via [RequestServiceProvider]
  /// - Should be cleaned up after the request using [cleanupRequestContainer]
  ///
  /// Parameters:
  /// - [request]: The HTTP request to scope the container to
  /// - [response]: The HTTP response associated with the request
  ///
  /// Returns a new container with request-scoped bindings.
  Container createRequestContainer(HttpRequest request, HttpResponse response) {
    final container = _container.createChild();
    container.instance<ConfigRegistry>(_configRegistry);
    final provider = RequestServiceProvider(request, response);
    provider.register(container);

    if (_container.has<Config>()) {
      final parentConfig = _container.get<Config>();
      container.instance<Config>(ScopedConfig(parentConfig));
    }
    return container;
  }

  /// Cleans up a request-scoped container.
  ///
  /// This method:
  /// 1. Calls cleanup on all service providers
  /// 2. Allows providers to perform any necessary resource cleanup
  ///
  /// This should be called after the request has been handled, typically
  /// in a finally block.
  Future<void> cleanupRequestContainer(Container container) async {
    for (final provider in _providers) {
      await provider.cleanup(container);
    }
  }

  /// Cleans up all registered service providers using the root container.
  Future<void> cleanupProviders() async {
    for (final provider in _providers) {
      await provider.cleanup(_container);
    }
  }

  Future<void> notifyProvidersOfConfigReload(Config config) async {
    for (final provider in _providers) {
      if (provider is ProvidesDefaultConfig) {
        await provider.onConfigReload(_container, config);
      }
    }
  }

  /// Makes an instance of type [T] from the container.
  ///
  /// This is a convenience method that delegates to the main container's
  /// [make] method.
  ///
  /// Example:
  /// ```dart
  /// final config = await make<Config>();
  /// ```
  Future<T> make<T>() => _container.make<T>();

  /// Checks if the container can resolve type [T].
  ///
  /// This is a convenience method that delegates to the main container's
  /// [has] method.
  ///
  /// Example:
  /// ```dart
  /// if (has<Logger>()) {
  ///   final logger = await make<Logger>();
  /// }
  /// ```
  bool has<T>() => _container.has<T>();

  void _ensureConfigRegistryRegistered() {
    if (_configRegistryBound) {
      return;
    }
    _container.instance<ConfigRegistry>(_configRegistry);
    _configRegistryBound = true;
  }
}
