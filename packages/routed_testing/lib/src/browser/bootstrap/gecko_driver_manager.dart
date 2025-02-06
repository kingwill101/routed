import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:routed_testing/src/browser/bootstrap/browser_paths.dart';
import 'driver_interface.dart';

class GeckoDriverManager implements WebDriverManager {
  Process? _driverProcess;
  static const _baseUrl =
      'https://github.com/mozilla/geckodriver/releases/download';
  static const _version = 'v0.33.0';
  @override
  Future<void> setup(String targetDir) async {
    print('Setting up GeckoDriver in: $targetDir');

    final driverUrl = _getDriverUrl();
    print('Downloading GeckoDriver from: $driverUrl');

    final archivePath = path.join(targetDir, 'geckodriver.archive');
    await _downloadDriver(driverUrl, archivePath);

    print('Extracting GeckoDriver... ');
    print("Archive path: $archivePath");
    print("targetDir: $targetDir");
    await _extractDriver(archivePath, targetDir);

    print('Cleaning up temporary files...');
    await File(archivePath).delete();

    print('GeckoDriver setup complete');
  }

  // Future<void> _downloadDriver(String url, String outputPath) async {
  //   final response = await http.get(Uri.parse(url));
  //   if (response.statusCode != 200) {
  //     throw Exception('Failed to download GeckoDriver: ${response.statusCode}');
  //   }
  //   await File(outputPath).writeAsBytes(response.bodyBytes);
  // }

  String _getDriverUrl() {
    final platform = _getCurrentPlatform();
    return '$_baseUrl/$_version/geckodriver-$_version-$platform';
  }

  String _getCurrentPlatform() {
    if (Platform.isLinux) return 'linux64.tar.gz';
    if (Platform.isMacOS) {
      return Platform.version.contains('arm')
          ? 'macos-aarch64.tar.gz'
          : 'macos.tar.gz';
    }
    return 'win64.zip';
  }

  Future<void> _extractDriver(String archivePath, String targetDir) async {
    print('Verifying archive exists: ${await File(archivePath).exists()}');
    print('Archive size: ${await File(archivePath).length()} bytes');

    // Use -xf instead of -xvzf since it's just a tar file
    final result = await Process.run('tar', [
      '-xf', // Extract, use archive file
      archivePath,
      '-C', // Change to directory
      targetDir
    ]);

    print('Extraction output: ${result.stdout}');
    print('Extraction errors: ${result.stderr}');
    print('Extraction exit code: ${result.exitCode}');

    // List contents after extraction
    final contents = Directory(targetDir).listSync();
    print(
        'Target directory contents: ${contents.map((e) => path.basename(e.path)).join(', ')}');

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

  Future<void> _downloadDriver(String url, String outputPath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download GeckoDriver: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    print('Downloaded ${bytes.length} bytes');

    await File(outputPath).writeAsBytes(bytes);
    print('Saved driver to: $outputPath');

    // Verify file was written
    final savedFile = File(outputPath);
    if (await savedFile.exists()) {
      print(
          'Verified file exists with size: ${await savedFile.length()} bytes');
    } else {
      throw Exception('Failed to save driver file');
    }
  }

  @override
  Future<void> start({int port = 4444}) async {
    final targetDir = BrowserPaths.getRegistryDirectory();
    final driverPath = path.join(targetDir, 'drivers', 'geckodriver');

    if (!await File(driverPath).exists()) {
      throw Exception('GeckoDriver not found at: $driverPath');
    }

    print('Starting GeckoDriver from: $driverPath');
    _driverProcess = await Process.start(
      driverPath,
      ['--port', port.toString()],
      mode: ProcessStartMode.detached,
    );

    print('Waiting for GeckoDriver to be ready...');
    await _waitForPort(port);
    print('GeckoDriver ready on port $port');
  }

  Future<void> _waitForPort(int port) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < Duration(seconds: 30)) {
      try {
        final socket = await Socket.connect('localhost', port);
        await socket.close();
        return;
      } catch (_) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    throw Exception('GeckoDriver failed to start on port $port');
  }

  @override
  Future<void> stop() async {
    if (_driverProcess != null) {
      _driverProcess!.kill();
      _driverProcess = null;
    }
  }

  @override
  Future<String> getVersion() async {
    final result = await Process.run('./geckodriver', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('Failed to get GeckoDriver version');
    }
    return result.stdout.toString().trim();
  }

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
