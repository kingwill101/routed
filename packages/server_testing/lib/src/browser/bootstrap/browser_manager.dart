import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/browser_json_loader.dart';

import '../browser_exception.dart';
import 'browser_json.dart';
import 'registry.dart';
import 'version.dart';

class BrowserManager {
  static const _baseDir = '.routed/browsers';
  static final Map<String, Version> _browserVersions = {
    'chrome': Version.parse('114.0.5735.90'),
    'firefox': Version.parse('113.0.1'),
  };

  static String? getBrowserPath(String browserName) {
    final version = _browserVersions[browserName];
    if (version == null) return null;

    final versionStr = version.toString();
    final installDir = path.join(_baseDir, browserName, versionStr);
    final executablePath = _getBrowserExecutablePath(browserName, installDir);

    return File(executablePath).existsSync() ? executablePath : null;
  }

  static String _getBrowserExecutablePath(String browser, String installDir) {
    if (Platform.isWindows) {
      return path.join(installDir, '$browser.exe');
    } else if (Platform.isMacOS) {
      return browser == 'chrome'
          ? path.join(
              installDir, 'Chromium.app', 'Contents', 'MacOS', 'Chromium')
          : path.join(installDir, browser);
    }
    return path.join(installDir, browser);
  }

  static Future<void> install(List<String> browsers) async {
    final registry = Registry(
      await BrowserJsonLoader.load(),
      requestedBrowser: browsers.first, // Pass the first browser as requested
    );

    final executables = browsers
        .map((b) => registry.getExecutable(b))
        .where((e) => e != null)
        .cast<Executable>()
        .toList();

    if (executables.isEmpty) {
      throw BrowserException('No valid browsers to install');
    }

    await registry.installExecutables(executables);
  }

  static Future<void> installBrowser(
    String browserName, {
    Version? version,
    bool force = false,
  }) async {
    version ??= _browserVersions[browserName];
    final versionStr = version?.toString();
    if (version == null) {
      throw Exception('Unsupported browser: $browserName');
    }

    final installDir = path.join(_baseDir, browserName, versionStr ?? 'latest');
    if (!force && await Directory(installDir).exists()) {
      print('$browserName $version is already installed');
      return;
    }

    print('Installing $browserName ${versionStr ?? 'latest'}...');

    final url = _getDownloadUrl(browserName, versionStr ?? 'latest');
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to download browser');
    }

    await _extractBrowser(response.bodyBytes, installDir);
    await _setPermissions(installDir);
  }

  static String _getDownloadUrl(String browser, String version) {
    final platform = _getPlatform();
    return 'https://browser.repository/$platform/$browser-$version.zip';
  }

  static String _getPlatform() {
    if (Platform.isWindows) return 'win64';
    if (Platform.isMacOS) return 'mac';
    if (Platform.isLinux) return 'linux';
    throw Exception('Unsupported platform');
  }

  static Future<void> _extractBrowser(List<int> bytes, String targetDir) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File(path.join(targetDir, filename))
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }
  }

  static Future<void> _setPermissions(String dir) async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['-R', '+x', dir]);
    }
  }
}
