import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'driver_interface.dart';

class ChromeDriverManager implements WebDriverManager {
  Process? _driverProcess;

  @override
  Future<void> setup(String targetDir) async {
    final metadata = await _fetchDriverMetadata();
    final chromeVersion = await _getInstalledChromeVersion();
    final majorVersion = chromeVersion.split('.').first;
    
    final driverUrl = _getDriverUrlForPlatform(
      metadata['milestones'][majorVersion]['downloads']['chromedriver'],
      _getCurrentPlatform()
    );
    
    final zipPath = path.join(targetDir, 'chromedriver.zip');
    await _downloadDriver(driverUrl, zipPath);
    await _extractDriver(zipPath, targetDir);
    await File(zipPath).delete();
  }

  Future<String> _getInstalledChromeVersion() async {
    final result = await Process.run('google-chrome', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('Chrome not found. Please install Chrome browser.');
    }
    // Output format: "Google Chrome XX.X.XXXX.XX"
    return result.stdout.toString().split(' ').last.trim();
  }

  String _getDriverUrlForPlatform(List<dynamic> downloads, String platform) {
    final download = downloads.firstWhere(
      (d) => d['platform'] == platform,
      orElse: () => throw Exception('No ChromeDriver available for platform: $platform'),
    );
    return download['url'];
  }

  Future<void> _downloadDriver(String url, String outputPath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download ChromeDriver: ${response.statusCode}');
    }
    await File(outputPath).writeAsBytes(response.bodyBytes);
  }

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
    throw Exception('ChromeDriver failed to start on port $port');
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
    final result = await Process.run('./chromedriver', ['--version']);
    if (result.exitCode != 0) {
      throw Exception('Failed to get ChromeDriver version');
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

  // Private helper methods
  Future<Map<String, dynamic>> _fetchDriverMetadata() async {
    final response = await http.get(Uri.parse(
      'https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone-with-downloads.json'
    ));
    return json.decode(response.body);
  }

  String _getCurrentPlatform() {
    if (Platform.isMacOS) {
      return Platform.version.contains('arm') ? 'mac-arm64' : 'mac-x64';
    }
    if (Platform.isLinux) return 'linux64';
    return 'win64';
  }
}