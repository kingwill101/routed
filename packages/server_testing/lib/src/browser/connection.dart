import 'dart:async';
import 'dart:io';

/// Utility class for checking and waiting for a network connection to a
/// host and port, typically used to wait for a WebDriver server to start.
class BrowserConnection {
  /// The hostname or IP address to connect to. Defaults to 'localhost'.
  final String host;
  /// The port number to connect to.
  final int port;
  /// The maximum duration to wait for a successful connection when calling
  /// [waitForConnection]. Defaults to 30 seconds.
  final Duration timeout;

  /// Creates a [BrowserConnection] helper targeting the specified [port] and
  /// optional [host] and [timeout].
  BrowserConnection({
    this.host = 'localhost',
    required this.port,
    this.timeout = const Duration(seconds: 30),
  });

  /// Waits until a successful TCP connection can be established to the configured
  /// [host] and [port].
  ///
  /// Attempts to connect repeatedly with a short delay until the connection
  /// succeeds or the configured [timeout] is reached.
  ///
  /// Throws a [TimeoutException] if the connection cannot be established within
  /// the timeout period.
  Future<void> waitForConnection() async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 1),
        );
        await socket.close();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    throw TimeoutException(
      'Failed to connect to browser on $host:$port',
      timeout,
    );
  }

  /// Checks if a connection can currently be established to the configured
  /// [host] and [port].
  ///
  /// Attempts a single connection and returns `true` if successful, `false` otherwise.
  Future<bool> isConnected() async {
    try {
      final socket = await Socket.connect(host, port);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
