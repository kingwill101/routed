/// Loads grouped and JSON translation messages from backing sources.
///
/// A grouped translation is addressed by a `locale` and `group`, for example
/// `en` and `messages`. A `namespace` identifies an optional vendor or
/// package-specific source. The wildcard group and namespace `*` are reserved
/// for flat locale JSON dictionaries.
abstract class TranslationLoader {
  /// Loads the messages for [locale], [group], and optional [namespace].
  ///
  /// When both [group] and [namespace] are `*`, the result is a flat map from
  /// JSON translation keys to their values. A missing source should be
  /// represented by an empty map rather than `null`.
  Map<String, dynamic> load(String locale, String group, {String? namespace});

  /// Associates [namespace] with a source path or implementation-specific hint.
  ///
  /// Registering an existing namespace replaces its previous hint. The hint
  /// is interpreted by the concrete loader; it may be a filesystem path, a
  /// package identifier, or a remote source key.
  void addNamespace(String namespace, String hint);

  /// Replaces the ordered base paths for grouped translations.
  ///
  /// Implementations commonly merge matching files from these paths in order,
  /// allowing later paths to provide overrides.
  void setPaths(Iterable<String> paths);

  /// Adds [path] to the grouped translation search paths.
  ///
  /// Adding a path that is already configured should not create an accidental
  /// duplicate search entry.
  void addPath(String path);

  /// Ordered grouped translation search paths currently configured.
  List<String> get paths;

  /// Replaces the ordered base paths for locale JSON dictionaries.
  ///
  /// Each path conventionally contains a file named `<locale>.json`.
  void setJsonPaths(Iterable<String> paths);

  /// Adds [path] to the locale JSON dictionary search paths.
  ///
  /// Adding a path that is already configured should not create an accidental
  /// duplicate search entry.
  void addJsonPath(String path);

  /// Ordered locale JSON dictionary search paths currently configured.
  List<String> get jsonPaths;

  /// Replaces all namespace-to-source mappings.
  ///
  /// Namespaces omitted from [namespaces] are removed from the configuration.
  void setNamespaces(Map<String, String> namespaces);

  /// Namespace-to-source mappings currently configured.
  ///
  /// The returned map is a configuration result, not a second mutation API;
  /// callers should not rely on mutating it to reconfigure the loader.
  Map<String, String> get namespaces;
}
