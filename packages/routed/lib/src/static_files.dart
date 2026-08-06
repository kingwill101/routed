mixin StaticFileHandler {
  void staticFile(String a, String b, [dynamic fs]) {}
  void static(
    String a,
    String b, {
    dynamic fileSystem,
    bool listDirectory = false,
  }) {}

  void staticFS(String a, dynamic b) {}
}
