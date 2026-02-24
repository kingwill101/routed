abstract class TranslationLoader {
  Map<String, dynamic> load(String locale, String group, {String? namespace});

  void addNamespace(String namespace, String hint);

  void setPaths(Iterable<String> paths);

  void addPath(String path);

  List<String> get paths;

  void setJsonPaths(Iterable<String> paths);

  void addJsonPath(String path);

  List<String> get jsonPaths;

  void setNamespaces(Map<String, String> namespaces);

  Map<String, String> get namespaces;
}
