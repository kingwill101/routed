class ViewExtensionRegistration {
  ViewExtensionRegistration({
    required this.engine,
    required this.apply,
    this.description = '',
  });

  final String engine;
  final void Function(Object target) apply;
  final String description;
}

/// Registry for provider-contributed view extensions.
class ViewExtensionRegistry {
  ViewExtensionRegistry._();

  static final ViewExtensionRegistry instance = ViewExtensionRegistry._();

  final Map<String, List<ViewExtensionRegistration>> _extensions = {};

  void register(ViewExtensionRegistration extension) {
    final key = _normalizeName(extension.engine);
    _extensions
        .putIfAbsent(key, () => <ViewExtensionRegistration>[])
        .add(extension);
  }

  void registerFor(String engine, void Function(Object target) apply) {
    register(ViewExtensionRegistration(engine: engine, apply: apply));
  }

  Iterable<ViewExtensionRegistration> extensionsFor(String engine) {
    return List<ViewExtensionRegistration>.unmodifiable(
      _extensions[_normalizeName(engine)] ??
          const <ViewExtensionRegistration>[],
    );
  }

  bool hasExtensions(String engine) {
    final bucket = _extensions[_normalizeName(engine)];
    return bucket != null && bucket.isNotEmpty;
  }

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
