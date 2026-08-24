/// Describes one callback contributed to a view engine.
///
/// The callback is retained by `ViewExtensionRegistry` and invoked whenever a
/// matching engine creates or prepares its extension target. A callback should
/// verify or cast the `target` argument to the engine-specific environment
/// type it expects;
/// errors from the callback are intentionally allowed to propagate so a
/// misconfigured provider cannot be silently ignored.
class ViewExtensionRegistration {
  /// Creates a registration for [engine] and its [apply] callback.
  ///
  /// Engine lookup trims surrounding whitespace and ignores case. [description]
  /// is metadata for diagnostics and does not affect registration or
  /// execution.
  ViewExtensionRegistration({
    required this.engine,
    required this.apply,
    this.description = '',
  });

  /// Engine name receiving the extension.
  ///
  /// The value is retained as supplied, while registry lookup treats names as
  /// case-insensitive and ignores surrounding whitespace.
  final String engine;

  /// Callback that mutates or configures the engine-specific target object.
  ///
  /// The target type is deliberately `Object` because each engine owns its
  /// environment type. Throwing from this callback stops the current engine
  /// setup and is visible to the render caller.
  final void Function(Object target) apply;

  /// Optional description used in diagnostics.
  final String description;
}

/// Process-wide registry for provider-contributed view extensions.
///
/// Registrations are applied in registration order. The registry has no
/// removal operation, so applications and tests that register process-wide
/// extensions should do so during startup and avoid registering the same
/// callback repeatedly.
class ViewExtensionRegistry {
  /// Creates the singleton registry.
  ViewExtensionRegistry._();

  /// The registry consulted by built-in and custom view engines.
  static final ViewExtensionRegistry instance = ViewExtensionRegistry._();

  final Map<String, List<ViewExtensionRegistration>> _extensions = {};

  /// Registers [extension] for its target engine.
  ///
  /// Multiple registrations for the same engine are retained and later
  /// applied in the order in which they were registered.
  void register(ViewExtensionRegistration extension) {
    final key = _normalizeName(extension.engine);
    _extensions
        .putIfAbsent(key, () => <ViewExtensionRegistration>[])
        .add(extension);
  }

  /// Registers [apply] as an extension for [engine].
  ///
  /// This is a shorthand for [register] when diagnostic metadata is not
  /// needed. The callback receives the engine-specific environment object.
  void registerFor(String engine, void Function(Object target) apply) {
    register(ViewExtensionRegistration(engine: engine, apply: apply));
  }

  /// Returns an immutable snapshot of registrations for [engine].
  ///
  /// The returned iterable is safe to inspect without changing the registry.
  /// It is empty when no matching registration exists.
  Iterable<ViewExtensionRegistration> extensionsFor(String engine) {
    return List<ViewExtensionRegistration>.unmodifiable(
      _extensions[_normalizeName(engine)] ??
          const <ViewExtensionRegistration>[],
    );
  }

  /// Whether [engine] has at least one registered extension.
  bool hasExtensions(String engine) {
    final bucket = _extensions[_normalizeName(engine)];
    return bucket != null && bucket.isNotEmpty;
  }

  /// Applies all registered extensions for [engine] to [target].
  ///
  /// Callbacks run in registration order. If a callback throws, later
  /// callbacks are not invoked and the exception is propagated to the caller.
  /// When no callbacks are registered, this method does nothing.
  void applyExtensions(String engine, Object target) {
    final bucket = _extensions[_normalizeName(engine)];
    if (bucket == null || bucket.isEmpty) {
      return;
    }
    for (final extension in bucket) {
      extension.apply(target);
    }
  }

  String _normalizeName(String name) => name.trim().toLowerCase();
}
