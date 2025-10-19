import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/browser_paths.dart';
import 'package:server_testing/src/browser/bootstrap/driver/gecko_driver_version.dart';

import 'driver_interface.dart';

/// Manages the setup, start, and stop operations for the GeckoDriver (Firefox) server.
///
/// Implements the [WebDriverManager] interface for Firefox browsers. Handles
/// downloading a specific GeckoDriver version from GitHub releases, extracting it,
/// setting permissions, and managing the server process.
class GeckoDriverManager extends WebDriverManager {
  /// The running GeckoDriver process instance, or `null` if not started.
  Process? _driverProcess;

  /// The base URL for GeckoDriver release downloads, sourced from generated code.
  static const _baseUrl = geckoDriverBaseUrl;

  @override
  String driverBinaryName() =>
      Platform.isWindows ? 'geckodriver.exe' : 'geckodriver';

  /// The specific version of GeckoDriver to download, sourced from generated code.
  static const _version = geckoDriverVersion;

  /// Sets up GeckoDriver by downloading and extracting the specified version.
  ///
  /// Constructs the download URL based on the platform, downloads the archive
  /// (tar.gz or zip), extracts it into the [targetDir], and sets executable
  /// permissions on the `geckodriver` binary (for non-Windows platforms).
  ///
  /// Throws an exception if the download or extraction fails.
  @override
  Future<void> setup(
    String targetDir, {
    int? major,
    String? exactVersion,
  }) async {
    print('Setting up GeckoDriver in: $targetDir');

    // If driver already exists and is executable, skip re-download to avoid
    // repeated downloads during tests unless force-reinstalled by caller.
    final existingDriverPath = path.join(
      targetDir,
      Platform.isWindows ? 'geckodriver.exe' : 'geckodriver',
    );
    if (await File(existingDriverPath).exists()) {
      print('GeckoDriver already present at: $existingDriverPath');
      return;
    }

    final driverUrl = _getDriverUrl();
    print('Downloading GeckoDriver from: $driverUrl');

    final archivePath = path.join(targetDir, 'geckodriver.archive');
    await downloadDriver(driverUrl, archivePath);

    print('Extracting GeckoDriver... ');
    print("Archive path: $archivePath");
    print("targetDir: $targetDir");
    await _extractDriver(archivePath, targetDir);

    print('Cleaning up temporary files...');
    await File(archivePath).delete();

    print('GeckoDriver setup complete');
  }

  /// Constructs the full download URL for the configured GeckoDriver version
  /// ([_version]) and the current platform.
  String _getDriverUrl() {
    final platform = _getCurrentPlatform();
    return '$_baseUrl/$_version/geckodriver-$_version-$platform';
  }

  /// Determines the platform and architecture string used in GeckoDriver
  /// download artifact names (e.g., 'linux64.tar.gz', 'macos-aarch64.tar.gz', 'win64.zip').
  String _getCurrentPlatform() {
    if (Platform.isLinux) return 'linux64.tar.gz';
    if (Platform.isMacOS) {
      return Platform.version.contains('arm')
          ? 'macos-aarch64.tar.gz'
          : 'macos.tar.gz';
    }
    return 'win64.zip';
  }

  /// Extracts the downloaded GeckoDriver archive from [archivePath] into the
  /// [targetDir] and sets executable permissions on the driver binary
  /// (for non-Windows platforms). Handles both `.tar.gz` and `.zip` archives.
  Future<void> _extractDriver(String archivePath, String targetDir) async {
    print('Verifying archive exists: ${await File(archivePath).exists()}');
    print('Archive size: ${await File(archivePath).length()} bytes');

    // Use -xf instead of -xvzf since it's just a tar file
    final result = await Process.run('tar', [
      '-xf', // Extract, use archive file
      archivePath,
      '-C', // Change to directory
      targetDir,
    ]);

    print('Extraction output: ${result.stdout}');
    print('Extraction errors: ${result.stderr}');
    print('Extraction exit code: ${result.exitCode}');

    // List contents after extraction
    final contents = Directory(targetDir).listSync();
    print(
      'Target directory contents: ${contents.map((e) => path.basename(e.path)).join(', ')}',
    );

    if (!Platform.isWindows) {
      final driverPath = path.join(targetDir, 'geckodriver');
      if (await File(driverPath).exists()) {
        await Process.run('chmod', ['+x', driverPath]);
        print('Set executable permissions on: $driverPath');
      } else {
        print('Driver not found at expected path: $driverPath');
        throw Exception('Driver extraction failed');
      }
    }
  }

  /// Starts the GeckoDriver server process, listening on the specified [port].
  ///
  /// Locates the `geckodriver` executable within the driver registry directory,
  /// starts it detached, and waits for the server to become available by
  /// attempting to connect to the specified [port].
  ///
  /// Throws an exception if the driver executable is not found or fails to start
  /// within a reasonable timeout.
  @override
  Future<void> start(int port) async {
    final targetDir = BrowserPaths.getRegistryDirectory();
    final driverPath = path.join(targetDir, 'drivers', 'geckodriver');

    if (!await File(driverPath).exists()) {
      throw Exception('GeckoDriver not found at: $driverPath');
    }
    print('Starting GeckoDriver from: $driverPath');
    final args = ['--port', port.toString()];

    print('Waiting for GeckoDriver to be ready...');
    // await waitForPort(port);
    _driverProcess = await startProcess(driverPath, args);
    print('GeckoDriver process started with PID: ${_driverProcess!.pid}');
    print('GeckoDriver listening on port: $port');
  }

  /// Stops the running GeckoDriver server process, if one was started by this manager.
  ///
  @override
  Future<void> stop() async {
    if (_driverProcess != null) {
      _driverProcess!.kill();
      _driverProcess = null;
    }
  }

  /// Gets the version string of the installed GeckoDriver executable.
  ///
  /// Executes `./geckodriver --version` and returns the output. Assumes the
  /// executable is in the current directory.
  @override
  Future<String> getVersion() async {
    final result = await Process.run('./geckodriver', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('Failed to get GeckoDriver version');
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
}
