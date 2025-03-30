/// Defines the interface for managing WebDriver server processes.
///
/// Implementations like [ChromeDriverManager] and [GeckoDriverManager] handle
/// the specific details of setting up, starting, stopping, and querying the
/// status of different WebDriver servers (e.g., ChromeDriver, GeckoDriver).
abstract class WebDriverManager {
  /// Ensures the WebDriver executable is downloaded, extracted, and ready
  /// for execution within the specified [targetDir].
  ///
  /// This may involve checking the installed browser version, downloading the
  /// correct driver version, extracting archives, and setting permissions.
  Future<void> setup(String targetDir);
  /// Starts the WebDriver server process, configuring it to listen on the
  /// specified [port].
  ///
  /// Should wait until the server is confirmed to be running and accepting
  /// connections before completing.
  Future<void> start({int port = 4444});
  /// Stops the running WebDriver server process managed by this instance.
  Future<void> stop();
  /// Gets the version string of the installed WebDriver executable.
  Future<String> getVersion();
  /// Checks if the WebDriver server is currently running and listening on the
  /// specified [port].
  Future<bool> isRunning(int port);
}
