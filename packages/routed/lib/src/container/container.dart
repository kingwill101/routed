import 'dart:async';

/// Describes the lifecycle scope of a container instance.
///
/// Root containers live for the application lifetime, while request
/// containers are created per request/connection and should be cleaned up
/// after each request.
enum ContainerScope {
  /// Application-level container.
  root,

  /// Request/connection scoped container.
  request,

  /// A child container with no explicit lifecycle semantics.
  child,
}

/// Represents a binding for a type, including its factory and singleton status.
///
/// A [Binding] manages the creation and lifecycle of a dependency within the container,
/// allowing for either transient or singleton instance management.
///
/// Example:
/// ```dart
/// final binding = Binding<MyService>(
///   (container) async => MyService(),
///   singleton: true,
/// );
/// ```
class Binding<T> {
  /// The factory function that creates instances of type [T].
  /// Takes a [Container] instance and returns a [Future<T>].
  final Future<T> Function(Container) factory;

  /// Whether this binding represents a singleton instance.
  /// If true, the same instance will be returned for all resolutions.
  final bool singleton;

  /// The cached instance for singleton bindings.
  /// Will be null for non-singleton bindings or before first resolution.
  T? _instance;

  /// Creates a new binding with the given factory function.
  ///
  /// Parameters:
  /// - [factory]: Function that creates instances of type [T]
  /// - [singleton]: Whether this binding is a singleton (defaults to false)
  /// - [instance]: Optional pre-existing instance for singleton bindings
  Binding(this.factory, {this.singleton = false, T? instance})
    : _instance = instance;

  /// Gets the cached instance if available
  // ignore: unnecessary_getters_setters
  T? get instance => _instance;

  /// Sets the cached instance
  // ignore: unnecessary_getters_setters
  set instance(T? value) => _instance = value;

  /// Resolves this binding to an instance of type [T].
  ///
  /// For singleton bindings, returns the cached instance if available,
  /// otherwise creates and caches a new instance.
  /// For non-singleton bindings, always creates a new instance.
  Future<T> resolve(Container container) async {
    if (singleton && _instance != null) {
      return _instance as T;
    }

    final instance = await container._resolve<T>(factory);
    if (singleton) {
      _instance = instance;
    }
    return instance;
  }
}

/// A lightweight dependency injection container for managing type bindings and resolving dependencies.
///
/// The container supports:
/// - Singleton and transient bindings
/// - Instance bindings
/// - Scoped bindings
/// - Type aliases
/// - Contextual bindings
/// - Resolution callbacks
/// - Parent/child container hierarchies
///
/// Example:
/// ```dart
/// final container = Container();
///
/// // Register a singleton
/// container.singleton<MyService>((c) async => MyService());
///
/// // Register a transient binding
/// container.bind<MyRepository>((c) async {
///   final service = await c.make<MyService>();
///   return MyRepository(service);
/// });
///
/// // Resolve a dependency
/// final instance = await container.make<MyRepository>();
/// ```
class Container {
  /// Map of type to binding
  final Map<Type, Binding<dynamic>> _bindings = {};

  /// Map of type to cached instances
  final Map<Type, dynamic> _instances = {};

  /// Map of type aliases
  final Map<Type, Type> _aliases = {};

  /// Map of contextual bindings
  final Map<Type, Map<Type, dynamic>> _contextual = {};

  /// Callbacks to run before resolving a type
  final Map<Type, List<Function>> _resolvingCallbacks = {};

  /// Callbacks to run after resolving a type
  final Map<Type, List<Function>> _afterResolvingCallbacks = {};

  /// Set of types that are scoped and should be cleared together
  final Set<Type> _scopedTypes = {};

  /// Optional parent container for hierarchical DI
  final Container? _parent;

  /// The lifecycle scope for this container.
  final ContainerScope _scope;

  /// Creates a new container, optionally with a parent container.
  Container({Container? parent, ContainerScope? scope})
    : _parent = parent,
      _scope = scope ?? (parent == null
          ? ContainerScope.root
          : ContainerScope.child);

  /// The lifecycle scope for this container.
  ContainerScope get scope => _scope;

  /// Whether this container represents an application root scope.
  bool get isRootScope => _scope == ContainerScope.root;

  /// Whether this container represents a request scope.
  bool get isRequestScope => _scope == ContainerScope.request;

  /// Binds a factory function for type [T].
  ///
  /// The factory function receives the container instance and returns a `Future<T>`.
  /// If [singleton] is true, the same instance will be returned for all resolutions.
  ///
  /// Example:
  /// ```dart
  /// container.bind<MyService>((c) async => MyService());
  /// ```
  void bind<T>(
    Future<T> Function(Container) factory, {
    bool singleton = false,
  }) {
    _bindings[T] = Binding<T>(factory, singleton: singleton);
  }

  /// Binds a singleton using a factory function.
  ///
  /// This is a convenience method equivalent to calling [bind] with singleton: true.
  ///
  /// Example:
  /// ```dart
  /// container.singleton<MyService>((c) async => MyService());
  /// ```
  void singleton<T>(Future<T> Function(Container) factory) {
    bind<T>(factory, singleton: true);
  }

  /// Binds a scoped singleton that will be cleared when [clearScoped] is called.
  ///
  /// Scoped bindings are useful for managing groups of related dependencies
  /// that should be cleaned up together.
  ///
  /// Example:
  /// ```dart
  /// container.scoped<RequestContext>((c) async => RequestContext());
  /// ```
  void scoped<T>(Future<T> Function(Container) factory) {
    _scopedTypes.add(T);
    singleton<T>(factory);
  }

  /// Clears all scoped instances from the container.
  ///
  /// This removes both the instances and bindings for all scoped types.
  void clearScoped() {
    for (final type in _scopedTypes) {
      _instances.remove(type);
      _bindings.remove(type);
    }
    _scopedTypes.clear();
  }

  /// Binds an existing instance directly.
  ///
  /// The instance will be treated as a singleton and returned for all resolutions.
  ///
  /// Example:
  /// ```dart
  /// final service = MyService();
  /// container.instance<MyService>(service);
  /// ```
  void instance<T>(T instance) {
    _instances[T] = instance;
    _bindings[T] = Binding<T>(
      (c) async => instance,
      singleton: true,
      instance: instance,
    );
  }

  /// Removes the binding and cached instance for type [T].
  ///
  /// Service providers can use this to release managed instances when
  /// configuration changes require rebuilding them.
  void remove<T>() {
    _instances.remove(T);
    _bindings.remove(T);
    _aliases.remove(T);
    _aliases.removeWhere((_, value) => value == T);
    _contextual.remove(T);
    for (final contextualBindings in _contextual.values) {
      contextualBindings.remove(T);
    }
    _resolvingCallbacks.remove(T);
    _afterResolvingCallbacks.remove(T);
    _scopedTypes.remove(T);
  }

  /// Adds a contextual binding that provides different implementations based on context.
  ///
  /// Parameters:
  /// - [concrete]: The concrete type that needs the dependency
  /// - [abstract]: The abstract type being bound
  /// - [implementation]: The implementation to use in this context
  void addContextualBinding(
    Type concrete,
    Type abstract,
    dynamic implementation,
  ) {
    _contextual[concrete] ??= {};
    _contextual[concrete]![abstract] = implementation;
  }

  /// Adds a callback to be run before resolving a type.
  ///
  /// The callback receives the resolved instance and container.
  ///
  /// Example:
  /// ```dart
  /// container.resolving<MyService>((service, container) {
  ///   service.initialize();
  /// });
  /// ```
  void resolving<T>(void Function(T instance, Container container) callback) {
    _resolvingCallbacks[T] ??= [];
    _resolvingCallbacks[T]!.add(callback);
  }

  /// Adds a callback to be run after resolving a type.
  ///
  /// The callback receives the resolved instance and container.
  ///
  /// Example:
  /// ```dart
  /// container.afterResolving<MyService>((service, container) {
  ///   print('MyService was resolved');
  /// });
  /// ```
  void afterResolving<T>(
    void Function(T instance, Container container) callback,
  ) {
    _afterResolvingCallbacks[T] ??= [];
    _afterResolvingCallbacks[T]!.add(callback);
  }

  /// Binds one type as an alias of another type.
  ///
  /// This is useful for binding interfaces to implementations.
  ///
  /// Example:
  /// ```dart
  /// container.alias<ServiceInterface, ServiceImplementation>();
  /// ```
  void alias<T, U>() {
    if (T == U) {
      throw StateError('Cannot alias a type to itself: ${T.toString()}');
    }
    _aliases[T] = U;
    bind<T>((container) async {
      final resolved = await container.make<U>();
      return resolved as T;
    });
  }

  /// Makes an instance of type [T].
  ///
  /// This will:
  /// 1. Check for existing instances
  /// 2. Check for contextual bindings
  /// 3. Check for aliases
  /// 4. Resolve from bindings
  /// 5. Execute callbacks
  ///
  /// Throws [StateError] if no binding is found.
  Future<T> make<T>() async {
    // Check for existing instance
    final existingInstance = _instances[T];
    if (existingInstance != null) {
      return existingInstance as T;
    }

    // Check for contextual binding
    if (_contextual.containsKey(T)) {
      final contextualImpl = _contextual[T]![T];
      if (contextualImpl != null) {
        return await _resolve(contextualImpl as Future<T> Function(Container));
      }
    }

    // Check for alias
    if (_aliases.containsKey(T)) {
      final aliasType = _aliases[T]!;
      final binding = _bindings[aliasType] ?? _parent?._bindings[aliasType];
      if (binding != null) {
        final instance = await binding.resolve(this);
        if (binding.singleton) {
          _instances[T] = instance;
        }
        return instance as T;
      }
      throw StateError('No binding found for aliased type $aliasType');
    }

    final binding = _bindings[T] ?? _parent?._bindings[T];
    if (binding == null) {
      throw StateError('No binding found for type $T');
    }

    final instance = await binding.resolve(this);

    // Cache instance if singleton
    if (binding.singleton) {
      _instances[T] = instance;
    }

    return instance as T;
  }

  /// Internal method to resolve a factory function and execute callbacks.
  Future<T> _resolve<T>(Future<T> Function(Container) factory) async {
    final instance = await factory(this);

    // Run resolving callbacks
    final callbacks = _resolvingCallbacks[T] ?? [];
    for (final callback in callbacks) {
      (callback as void Function(T, Container))(instance, this);
    }

    // Run after resolving callbacks
    final afterCallbacks = _afterResolvingCallbacks[T] ?? [];
    for (final callback in afterCallbacks) {
      (callback as void Function(T, Container))(instance, this);
    }

    return instance;
  }

  /// Checks if a binding exists for type [T].
  ///
  /// This checks bindings, instances, aliases, and parent container.
  bool has<T>() {
    return _bindings.containsKey(T) ||
        _instances.containsKey(T) ||
        _aliases.containsKey(T) ||
        (_parent?.has<T>() ?? false);
  }

  /// Creates a child container that inherits bindings from this container.
  ///
  /// The child container can override bindings while maintaining access to parent bindings.
  Container createChild({ContainerScope scope = ContainerScope.child}) {
    return Container(parent: this, scope: scope);
  }

  /// Resolves multiple dependencies in parallel.
  ///
  /// Parameters:
  /// - [types]: List of types to resolve
  ///
  /// Returns a list of resolved instances in the same order as the input types.
  Future<List<dynamic>> makeAll(List<Type> types) async {
    return await Future.wait(
      types.map((type) {
        final binding = _bindings[type] ?? _parent?._bindings[type];
        if (binding == null) {
          throw StateError('No binding found for type $type');
        }
        return binding.resolve(this);
      }),
    );
  }

  /// Gets an instance of type [T] synchronously.
  ///
  /// This only works for:
  /// - Already resolved singleton instances
  /// - Directly bound instances
  ///
  /// Throws [StateError] if no synchronously available instance is found.
  T get<T>() {
    final instance = _instances[T];
    if (instance != null) {
      return instance as T;
    }

    final binding = _bindings[T] ?? _parent?._bindings[T];
    if (binding == null) {
      throw StateError('Type $T is not registered');
    }

    if (binding.instance != null) {
      return binding.instance as T;
    }

    throw StateError('No sync instance available for type $T');
  }

  /// Cleans up resources held by the container.
  ///
  /// This method should be called when the container is no longer needed.
  /// It will properly dispose of any resources and singletons.
  Future<void> cleanup() async {
    // Clean up singletons that need disposal
    for (final instance in _instances.values) {
      if (instance is Disposable) {
        await (instance).dispose();
      }
    }

    _instances.clear();
    _bindings.clear();
  }
}

/// Interface for objects that need cleanup when disposed.
abstract class Disposable {
  /// Disposes of any resources held by this object.
  Future<void> dispose();
}
