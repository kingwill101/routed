import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'driver_interface.dart';

/// Manages the setup, start, and stop operations for the ChromeDriver server.
///
/// Implements the [WebDriverManager] interface for Chrome/Chromium browsers.
/// Handles downloading the appropriate ChromeDriver version based on the
/// installed Chrome browser and managing the server process.
class ChromeDriverManager implements WebDriverManager {
  /// The running ChromeDriver process instance, or `null` if not started.
  Process? _driverProcess;

  /// Sets up ChromeDriver by downloading and extracting the correct version.
  ///
  /// Determines the required ChromeDriver version based on the locally installed
  /// Chrome browser version, fetches the download URL from the official
  /// metadata, downloads the archive, extracts it into the specified
  /// [targetDir], and sets executable permissions.
  ///
  /// Throws an exception if Chrome is not installed, the required ChromeDriver
  /// version is unavailable, or if download/extraction fails.
  @override
  Future<void> setup(String targetDir) async {
    final metadata = await _fetchDriverMetadata();
    final chromeVersion = await _getInstalledChromeVersion();
    final majorVersion = chromeVersion.split('.').first;

    final driverUrl = _getDriverUrlForPlatform(
        metadata['milestones'][majorVersion]['downloads']['chromedriver'] as List,
        _getCurrentPlatform());

    final zipPath = path.join(targetDir, 'chromedriver.zip');
    await _downloadDriver(driverUrl, zipPath);
    await _extractDriver(zipPath, targetDir);
    await File(zipPath).delete();
  }

  /// Attempts to find the version of the installed Google Chrome browser.
  ///
  /// Executes `google-chrome --version` and parses the output. Throws an
  /// exception if Chrome is not found in the system path.
  Future<String> _getInstalledChromeVersion() async {
    final result = await Process.run('google-chrome', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('Chrome not found. Please install Chrome browser.');
    }
    // Output format: "Google Chrome XX.X.XXXX.XX"
    return result.stdout.toString().split(' ').last.trim();
  }

  /// Finds the appropriate download URL from the metadata [downloads] list
  /// for the given target [platform] identifier (e.g., 'linux64', 'mac-x64').
  String _getDriverUrlForPlatform(List<dynamic> downloads, String platform) {
    final download = downloads.firstWhere(
      (d) => d['platform'] == platform,
      orElse: () =>
          throw Exception('No ChromeDriver available for platform: $platform'),
    );
    return download['url'] as String;
  }

  /// Downloads the ChromeDriver archive from the given [url] and saves it
  /// to [outputPath].
  Future<void> _downloadDriver(String url, String outputPath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to download ChromeDriver: ${response.statusCode}');
    }
    await File(outputPath).writeAsBytes(response.bodyBytes);
  }

  /// Extracts the downloaded ChromeDriver archive from [zipPath] into the
  /// [targetDir] and sets executable permissions on the driver binary
  /// (for non-Windows platforms).
  Future<void> _extractDriver(String zipPath, String targetDir) async {
    if (Platform.isWindows) {
      await Process.run('tar', ['-xf', zipPath], workingDirectory: targetDir);
    } else {
      await Process.run('unzip', ['-o', zipPath], workingDirectory: targetDir);
    }

    // Set executable permissions on Unix-like systems
    if (!Platform.isWindows) {
      final driverPath = path.join(targetDir, 'chromedriver');
      await Process.run('chmod', ['+x', driverPath]);
    }
  }

  /// Starts the ChromeDriver server process, listening on the specified [port].
  ///
  /// Locates the `chromedriver` executable (assumed to be in the current directory
  /// or PATH after setup), starts it detached, and waits for the server to become
  /// available by attempting to connect to the specified [port].
  ///
  /// Throws an exception if the driver executable is not found or fails to start
  /// within a reasonable timeout.
  @override
  Future<void> start({int port = 4444}) async {
    final driverPath = path.join(Directory.current.path, 'chromedriver');
    _driverProcess = await Process.start(
      driverPath,
      ['--port=$port'],
      mode: ProcessStartMode.detached,
    );

    // Wait for driver to be ready
    await _waitForPort(port);
  }

  /// Waits for a network service to start listening on the specified [port]
  /// on localhost.
  ///
  /// Attempts to establish a socket connection periodically until successful or
  /// a timeout (30 seconds) is reached. Throws an exception on timeout.
  Future<void> _waitForPort(int port) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 30)) {
      try {
        final socket = await Socket.connect('localhost', port);
        await socket.close();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw Exception('ChromeDriver failed to start on port $port');
  }

  /// Stops the running ChromeDriver server process, if one was started by this manager.
  ///
  @override
  Future<void> stop() async {
    if (_driverProcess != null) {
      _driverProcess!.kill();
      _driverProcess = null;
    }
  }

  /// Gets the version string of the installed ChromeDriver executable.
  ///
  /// Executes `./chromedriver --version` and returns the output. Assumes the
  /// executable is in the current directory.
  @override
  Future<String> getVersion() async {
    final result = await Process.run('./chromedriver', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('Failed to get ChromeDriver version');
    }
    return result.stdout.toString().trim();
  }

  /// Checks if a process is actively listening on the specified [port] on localhost.
  ///
  @override
  Future<bool> isRunning(int port) async {
    try {
      final socket = await Socket.connect('localhost', port);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the official JSON metadata containing ChromeDriver download URLs
  /// mapped by Chrome milestone versions.


  Future<Map<String, dynamic>> _fetchDriverMetadata() async {
    final response = await http.get(Uri.parse(
        'https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone-with-downloads.json'));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Determines the platform identifier string used by ChromeDriver downloads
  /// (e.g., 'mac-arm64', 'mac-x64', 'linux64', 'win64').
  String _getCurrentPlatform() {
    if (Platform.isMacOS) {
      return Platform.version.contains('arm') ? 'mac-arm64' : 'mac-x64';
    }
    if (Platform.isLinux) return 'linux64';
    return 'win64';
  }
}
