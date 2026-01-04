import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/browser_paths.dart';
import 'package:server_testing/src/browser/bootstrap/driver/chrome_driver_version.dart';
import 'package:server_testing/src/browser/bootstrap/platform_info.dart';

import 'driver_interface.dart';

/// Manages the setup, start, and stop operations for the ChromeDriver server.
///
/// Implements the [WebDriverManager] interface for Chrome/Chromium browsers.
/// Handles downloading the appropriate ChromeDriver version and managing the server process.
class ChromeDriverManager extends WebDriverManager {
  /// The running ChromeDriver process instance, or `null` if not started.
  Process? _driverProcess;
  static final Map<String, _VersionProbeCache> _versionProbeCache = {};
  static const Duration _versionProbeCacheTtl = Duration(minutes: 10);

  /// Sets up ChromeDriver by downloading and extracting the correct version.
  @override
  String driverBinaryName() =>
      Platform.isWindows ? 'chromedriver.exe' : 'chromedriver';

  ///
  /// Uses the pre-determined ChromeDriver version and platform-specific URL
  /// from the generated constants to download and extract ChromeDriver into
  /// the specified [targetDir].
  ///
  /// Throws an exception if the download or extraction fails.
  @override
  Future<void> setup(
    String targetDir, {
    int? major,
    String? exactVersion,
  }) async {
    print('Setting up ChromeDriver in: $targetDir');

    // If driver already exists and is executable, skip re-download to avoid
    // repeated downloads during tests unless force-reinstalled by caller.
    final existingDriverPath = path.join(
      targetDir,
      Platform.isWindows ? 'chromedriver.exe' : 'chromedriver',
    );
    if (await File(existingDriverPath).exists()) {
      print('ChromeDriver already present at: $existingDriverPath');
      return;
    }

    // Determine platform key for download using PlatformInfo
    final platformKey = _getPlatformKey();
    print('Current platform identified as: $platformKey');

    if (!chromeDriverFilenames.containsKey(platformKey)) {
      throw Exception('No ChromeDriver filename for platform: $platformKey');
    }

    final filename = chromeDriverFilenames[platformKey]!;

    // Resolve version dynamically: env > exactVersion > major > generated default
    final envExact =
        Platform.environment['SERVER_TESTING_CHROMEDRIVER_VERSION'];
    final envMajor = Platform.environment['SERVER_TESTING_CHROMEDRIVER_MAJOR'];
    final resolvedExact = envExact ?? exactVersion;
    final resolvedMajor = int.tryParse(envMajor ?? '') ?? major;
    final detectedMajor = await _detectChromeMajorFromBinary();

    String versionPath;
    if (resolvedExact != null) {
      versionPath = resolvedExact;
    } else if (resolvedMajor != null) {
      versionPath =
          await _fetchLatestForMajor(resolvedMajor) ?? chromeDriverVersion;
    } else {
      if (detectedMajor != null) {
        versionPath =
            await _fetchLatestForMajor(detectedMajor) ?? chromeDriverVersion;
      } else {
        versionPath = chromeDriverVersion;
      }
    }

    final downloadUrl =
        '$chromeDriverBaseUrl/$versionPath/$platformKey/$filename';

    print('Using ChromeDriver download URL: $downloadUrl');
    print('Expected filename: $filename');

    final zipPath = path.join(targetDir, 'chromedriver.zip');
    await downloadDriver(downloadUrl, zipPath);

    print('Extracting ChromeDriver...');
    await _extractDriver(zipPath, targetDir, platformKey);

    print('Cleaning up temporary files...');
    await File(zipPath).delete();

    print('ChromeDriver setup complete');
  }

  /// Gets the platform key for ChromeDriver download.
  /// This is used for directory naming in the extracted files.
  String _getPlatformKey() {
    final platform = PlatformInfo.currentPlatform;
    final platformId = PlatformInfo.platformId;

    // Map PlatformInfo data to ChromeDriver platform keys
    switch (platform) {
      case BrowserPlatform.linux:
        return 'linux64';
      case BrowserPlatform.mac:
        return platformId.contains('arm64') ? 'mac-arm64' : 'mac-x64';
      case BrowserPlatform.win:
        // For Windows, we might need to distinguish between 32-bit and 64-bit
        if (platformId.contains('32') ||
            Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ==
                'x86') {
          return 'win32';
        }
        return 'win64';
    }
  }

  /// Extracts the downloaded ChromeDriver archive from [zipPath] into the
  /// [targetDir] and sets executable permissions on the driver binary

  Future<String?> _fetchLatestForMajor(int major) async {
    try {
      final uri = Uri.parse(
        'https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone-with-downloads.json',
      );
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return null;
      final data = resp.body;
      final map = jsonDecode(data) as Map<String, dynamic>;
      final milestones = map['milestones'] as Map<String, dynamic>;
      final entry =
          milestones['$major'] as Map<String, dynamic>? ??
          milestones['$major.0'] as Map<String, dynamic>?;
      if (entry == null) return null;
      final v = entry['version'] as String?;
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _detectChromeMajorFromBinary() async {
    const timeout = Duration(seconds: 5);
    for (final candidate in _chromeBinaryCandidates()) {
      if (!await File(candidate).exists()) continue;
      final cached = _versionProbeCache[candidate];
      if (cached != null &&
          DateTime.now().difference(cached.timestamp) < _versionProbeCacheTtl) {
        return cached.major;
      }
      Process? process;
      try {
        process = await Process.start(candidate, ['--version']);
        final stdoutFuture = process.stdout.transform(utf8.decoder).join();
        final stderrFuture = process.stderr.transform(utf8.decoder).join();
        final exitCode = await process.exitCode.timeout(timeout);
        if (exitCode != 0) {
          _versionProbeCache[candidate] = _VersionProbeCache(null);
          continue;
        }
        final output = await stdoutFuture;
        await stderrFuture;
        final match = RegExp(r'(\d+)\.').firstMatch(output);
        if (match != null) {
          final major = int.tryParse(match.group(1) ?? '');
          _versionProbeCache[candidate] = _VersionProbeCache(major);
          return major;
        }
        _versionProbeCache[candidate] = _VersionProbeCache(null);
      } on TimeoutException {
        process?.kill();
        print(
          'Timed out probing Chrome version for $candidate; skipping version detection.',
        );
        _versionProbeCache[candidate] = _VersionProbeCache(null);
      } catch (_) {
        process?.kill();
        _versionProbeCache[candidate] = _VersionProbeCache(null);
        // Ignore and continue searching.
      }
    }
    return null;
  }

  Iterable<String> _chromeBinaryCandidates() sync* {
    final envOverrides = <String>[
      'SERVER_TESTING_CHROME_BINARY',
      'SERVER_TESTING_CHROMIUM_BINARY',
    ];
    for (final key in envOverrides) {
      final value = Platform.environment[key];
      if (value != null && value.trim().isNotEmpty) {
        yield value.trim();
      }
    }

    final registryDir = BrowserPaths.getRegistryDirectory();
    final relPath = BrowserPaths.getExecutablePath('chromium');
    if (relPath == null) return;

    final registry = Directory(registryDir);
    if (!registry.existsSync()) return;

    for (final entity in registry.listSync()) {
      if (entity is! Directory) continue;
      final name = path.basename(entity.path);
      if (!name.startsWith('chromium-') && !name.startsWith('chrome-')) {
        continue;
      }
      yield path.join(entity.path, relPath);
    }
  }

  /// (for non-Windows platforms).
  Future<void> _extractDriver(
    String zipPath,
    String targetDir,
    String platformKey,
  ) async {
    print('Verifying archive exists: ${await File(zipPath).exists()}');
    print('Archive size: ${await File(zipPath).length()} bytes');

    if (Platform.isWindows) {
      final result = await Process.run('tar', [
        '-xf',
        zipPath,
      ], workingDirectory: targetDir);
      print('Extraction exit code: ${result.exitCode}');
    } else {
      final result = await Process.run('unzip', [
        '-o',
        zipPath,
      ], workingDirectory: targetDir);
      print('Extraction output: ${result.stdout}');
      print('Extraction errors: ${result.stderr}');
      print('Extraction exit code: ${result.exitCode}');
    }

    // List contents after extraction
    final contents = Directory(targetDir).listSync();
    print(
      'Target directory contents: ${contents.map((e) => path.basename(e.path)).join(', ')}',
    );

    // Construct the expected directory name after extraction (may vary by platform)
    final extractedDirName = 'chromedriver-$platformKey';

    // Set executable permissions on Unix-like systems
    if (!Platform.isWindows) {
      // Try to find the chromedriver binary - it could be directly in the target dir
      // or in a subdirectory depending on the zip structure
      String? driverPath;

      // First check if it's in an expected subdirectory
      final extractedDirPath = path.join(targetDir, extractedDirName);
      final expectedPath = path.join(extractedDirPath, 'chromedriver');
      if (await File(expectedPath).exists()) {
        driverPath = expectedPath;
      } else {
        // Try to find it by searching recursively
        print('Driver not at expected path: $expectedPath');
        print('Searching for chromedriver binary...');

        // Look for the chromedriver binary in the extracted contents
        driverPath = await _findDriverBinary(targetDir, 'chromedriver');
      }

      if (driverPath == null) {
        print('Failed to locate chromedriver binary in extracted contents');
        throw Exception('Driver extraction failed - could not find binary');
      }

      // Set executable permissions
      await Process.run('chmod', ['+x', driverPath]);
      print('Set executable permissions on: $driverPath');

      // Move the executable to the target directory root for easier access
      final destPath = path.join(targetDir, 'chromedriver');
      final destFile = File(destPath);
      if (await destFile.exists()) {
        print('Destination already exists, keeping existing: $destPath');
      } else {
        await File(driverPath).copy(destPath);
        print('Copied driver to: $destPath');
      }
    } else {
      // For Windows, the executable might have .exe extension
      final driverPath = await _findDriverBinary(targetDir, 'chromedriver.exe');
      if (driverPath == null) {
        print('Failed to locate chromedriver.exe in extracted contents');
        throw Exception('Driver extraction failed - could not find binary');
      }

      // Move the executable to the target directory root for easier access
      final destPath = path.join(targetDir, 'chromedriver.exe');
      await File(driverPath).copy(destPath);
      print('Copied driver to: $destPath');
    }
  }

  /// Recursively searches for a driver binary with the specified [binaryName]
  /// in the [directory] and its subdirectories.
  Future<String?> _findDriverBinary(String directory, String binaryName) async {
    final dir = Directory(directory);
    final entities = await dir.list(recursive: true).toList();

    for (final entity in entities) {
      if (entity is File && path.basename(entity.path) == binaryName) {
        return entity.path;
      }
    }

    return null;
  }

  /// Starts the ChromeDriver server process, listening on the specified [port].
  ///
  /// Locates the `chromedriver` executable within the driver registry directory,
  /// starts it detached, and waits for the server to become available by
  /// attempting to connect to the specified [port].
  ///
  /// Throws an exception if the driver executable is not found or fails to start
  /// within a reasonable timeout.
  @override
  Future<void> start(int port) async {
    final targetDir = BrowserPaths.getRegistryDirectory();
    final driversDir = path.join(targetDir, 'drivers');
    final logPath = path.join(driversDir, 'chromedriver.log');
    final args = ['--port=$port', '--verbose', '--log-path=$logPath'];
    String driverPath;
    if (Platform.isWindows) {
      driverPath = path.join(driversDir, 'chromedriver.exe');
    } else {
      driverPath = path.join(driversDir, 'chromedriver');
    }

    if (!await File(driverPath).exists()) {
      throw Exception('ChromeDriver not found at: $driverPath');
    }
    print('Starting ChromeDriver from: $driverPath');

    _driverProcess = await startProcess(driverPath, args);

    print('ChromeDriver process started with PID: ${_driverProcess!.pid}');
    print('Waiting for ChromeDriver to be ready...');
    await waitForPort(port);
    print('ChromeDriver listening on port: $port');
  }

  /// Waits for a network service to start listening on the specified [port]
  /// on localhost.
  ///
  /// Attempts to establish a socket connection periodically until successful or
  /// a timeout (30 seconds) is reached. Throws an exception on timeout.
  // ignore: unused_element
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
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _VersionProbeCache {
  _VersionProbeCache(this.major) : timestamp = DateTime.now();

  final int? major;
  final DateTime timestamp;
}
