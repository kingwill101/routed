import 'dart:io';

import 'package:http/http.dart' as http;

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
  Future<void> setup(String targetDir, {int? major, String? exactVersion});

  /// Starts the WebDriver server process, configuring it to listen on the
  /// specified [port].
  ///
  /// Should wait until the server is confirmed to be running and accepting
  /// connections before completing.
  Future<void> start(int port);

  /// Stops the running WebDriver server process managed by this instance.
  Future<void> stop();

  /// Gets the version string of the installed WebDriver executable.
  Future<String> getVersion();

  /// Checks if the WebDriver server is currently running and listening on the
  /// specified [port].
  Future<bool> isRunning(int port);

  /// Waits for a network service to start listening on the specified [port]
  /// on localhost.
  ///
  /// Attempts to establish a socket connection periodically until successful or
  /// a timeout (30 seconds) is reached. Throws an exception on timeout.
  Future<void> waitForPort(
    int port, [
    Duration duration = const Duration(seconds: 30),
  ]) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < duration) {
      try {
        final socket = await Socket.connect('localhost', port);
        await socket.close();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw Exception('failed to start on port $port');
  }

  String driverBinaryName();

  Future<Process> startProcess(
    String executablePath,
    List<String> arguments,
  ) async {
    final process = await Process.start(executablePath, arguments);

    process.stdout.listen((event) {
      print('stdout: $event');
      String.fromCharCodes(event).split('\n').forEach(print);
    });
    process.stderr.listen((List<int> event) {
      String.fromCharCodes(event).split('\n').forEach(print);
    });
    process.exitCode.then((exitCode) {
      print('exited with code: $exitCode');
    });
    return process;
  }

  /// Downloads the GeckoDriver archive from the given [url] and saves it
  /// to [outputPath]. Verifies the download was successful and the file was saved.
  Future<void> downloadDriver(String url, String outputPath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download driver: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    print('Downloaded ${bytes.length} bytes');

    await File(outputPath).writeAsBytes(bytes);
    print('Saved driver to: $outputPath');

    // Verify file was written
    final savedFile = File(outputPath);
    if (await savedFile.exists()) {
      print(
        'Verified file exists with size: ${await savedFile.length()} bytes',
      );
    } else {
      throw Exception('Failed to save driver file');
    }
  }
}
