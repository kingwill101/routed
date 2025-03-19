abstract class WebDriverManager {
  Future<void> setup(String targetDir);
  Future<void> start({int port = 4444});
  Future<void> stop();
  Future<String> getVersion();
  Future<bool> isRunning(int port);
}
