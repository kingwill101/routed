/// Describes one provider-contributed extension application.
class ViewExtensionRegistration {
  /// Creates a registration for [engine] and its [apply] callback.
  ViewExtensionRegistration({
    required this.engine,
    required this.apply,
    this.description = '',
  });

  /// Engine name receiving the extension.
  final String engine;

  /// Callback that mutates or configures the target engine object.
  final void Function(Object target) apply;

  /// Optional description of the extension for diagnostics.
  final String description;
}

/// Registry for provider-contributed view extensions.
class ViewExtensionRegistry {
  /// The process-wide registry used by view engines.
  ViewExtensionRegistry._();

  /// The process-wide registry used by view engines.
  static final ViewExtensionRegistry instance = ViewExtensionRegistry._();

  final Map<String, List<ViewExtensionRegistration>> _extensions = {};

  /// Registers [extension] for its target engine.
  void register(ViewExtensionRegistration extension) {
    final key = _normalizeName(extension.engine);
    _extensions
        .putIfAbsent(key, () => <ViewExtensionRegistration>[])
        .add(extension);
  }

  /// Registers [apply] as an extension for [engine].
  void registerFor(String engine, void Function(Object target) apply) {
    register(ViewExtensionRegistration(engine: engine, apply: apply));
  }

  /// Returns the immutable registrations for [engine].
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
