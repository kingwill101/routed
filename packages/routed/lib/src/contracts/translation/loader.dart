/// Defines how translation lines are loaded from storage.
///
/// Implementations may source translations from the local filesystem,
/// remote services, or any other backing store, but they all expose the
/// same synchronous contract so higher-level components (validators, views,
/// middleware) can resolve messages without awaiting async work.
abstract class TranslationLoader {
  /// Loads the translation lines for the given [locale] and [group].
  ///
  /// When both [group] and [namespace] are `*`, implementations MUST return
  /// flat key/value pairs sourced from locale JSON dictionaries. This mirrors
  /// Laravel's loader contract so JSON-only helpers behave consistently.
  Map<String, dynamic> load(
    String locale,
    String group, {
    String? namespace,
  });

  /// Adds or replaces the directory hints for vendor namespaces.
  ///
  /// For example, registering the namespace `auth` with `/path/to/lang` allows
  /// lookups using `auth::messages.failed`.
  void addNamespace(String namespace, String hint);

  /// Replaces the configured base paths that should be scanned for
  /// `locale/group.(yaml|yml|json)` files.
  void setPaths(Iterable<String> paths);

  /// Appends a single base path if it is not already registered.
  void addPath(String path);

  /// Returns the configured base paths (read-only snapshot).
  List<String> get paths;

  /// Replaces the configured JSON dictionary paths (each should contain
  /// `<locale>.json` files).
  void setJsonPaths(Iterable<String> paths);

  /// Appends an additional JSON path if it is not already registered.
  void addJsonPath(String path);

  /// Returns the configured JSON dictionary paths (read-only snapshot).
  List<String> get jsonPaths;

  /// Replaces the namespace hint map, removing any namespaces that are no
  /// longer present.
  void setNamespaces(Map<String, String> namespaces);

  /// Returns the namespace hint map (read-only snapshot).
  Map<String, String> get namespaces;
}
