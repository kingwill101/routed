/// Loads translation messages from one or more backing sources.
abstract class TranslationLoader {
  /// Loads [group] for [locale] and an optional [namespace].
  Map<String, dynamic> load(String locale, String group, {String? namespace});

  /// Associates [namespace] with a source path or hint.
  void addNamespace(String namespace, String hint);

  /// Replaces the grouped translation [paths].
  void setPaths(Iterable<String> paths);

  /// Adds one grouped translation [path].
  void addPath(String path);

  /// Grouped translation paths currently configured.
  List<String> get paths;

  /// Replaces the JSON translation [paths].
  void setJsonPaths(Iterable<String> paths);

  /// Adds one JSON translation [path].
  void addJsonPath(String path);

  /// JSON translation paths currently configured.
  List<String> get jsonPaths;

  /// Replaces namespace-to-source mappings.
  void setNamespaces(Map<String, String> namespaces);

  /// Namespace-to-source mappings currently configured.
  Map<String, String> get namespaces;
}
