abstract class Config {
  bool has(String key);

  T? get<T>(String key, [T? defaultValue]);

  T getOrThrow<T>(String key, {String? message});

  Map<String, dynamic> all();

  void set(String key, dynamic value);

  void prepend(String key, dynamic value);

  void push(String key, dynamic value);

  void merge(Map<String, dynamic> values);

  void mergeDefaults(Map<String, dynamic> values);
}
