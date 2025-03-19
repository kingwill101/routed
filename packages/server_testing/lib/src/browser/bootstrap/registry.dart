import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/downloader.dart';
import 'package:server_testing/src/browser/bootstrap/installation.dart';

import '../browser_exception.dart';
import 'browser_json.dart';
import 'browser_paths.dart';
import 'lock.dart';
import 'platform_info.dart';

Executable? _createExecutableStatic(
  BrowserDescriptor descriptor,
  String registryDir,
) {
  String executablePath = BrowserPaths.getExecutablePath(descriptor.name) ?? "";
  if (executablePath.isEmpty) return null;
  executablePath = path.join(descriptor.dir, executablePath);

  final urls = BrowserPaths.getDownloadUrls(
    descriptor.name,
    descriptor.revision,
  );
  return Executable(
    type: ExecutableType.browser,
    name: descriptor.name,
    browserName: descriptor.browserName,
    directory: descriptor.dir,
    installType: descriptor.installByDefault
        ? InstallType.downloadByDefault
        : InstallType.downloadOnDemand,
    downloadURLs: urls,
    browserVersion: descriptor.browserVersion,
    executablePath: () => executablePath,
    executablePathOrDie: (String sdkLanguage) {
      if (!File(executablePath).existsSync()) {
        throw BrowserException(
          'Browser ${descriptor.name} is not installed. Run installation command.',
        );
      }
      return executablePath;
    },
    validateHostRequirements: (String r) async {
// Platform-specific validation implementation
    },
    install: () async {
      if (File(executablePath).existsSync()) {
        print('${descriptor.name} is already installed.');
        return;
      } else {
        await _downloadExecutableStatic(descriptor, urls);
      }
    },
  );
}

Future<void> _downloadExecutableStatic(BrowserDescriptor descriptor,
    [List<String> urls = const []]) async {
  urls = urls.isNotEmpty ? urls : Registry._getDownloadUrlsStatic(descriptor);
  if (urls.isEmpty) {
    throw BrowserException(
        'No download URL for ${descriptor.name} on ${PlatformInfo.platformId}');
  }

  print('Downloading ${descriptor.name} from available mirrors...');

  for (final url in urls) {
    try {
      print('Attempting download from: $url');
      await Registry._downloadAndExtractStatic(
          url, descriptor, BrowserPaths.getRegistryDirectory());
      print('Successfully downloaded and extracted ${descriptor.name}');
      return;
    } catch (e) {
      print('Failed to download from $url: $e');
      continue;
    }
  }

  throw BrowserException('Failed to download ${descriptor.name}');
}

class Registry {
  final String registryDir;
  final List<BrowserDescriptor> descriptors;
  final List<Executable> _executables;

  Registry._({
    required this.registryDir,
    required this.descriptors,
    required List<Executable> executables,
  }) : _executables = executables;

  factory Registry(BrowserJson browsersJson,
      {required String requestedBrowser}) {
    final registryDir = BrowserPaths.getRegistryDirectory();

    // Map common browser names to their registry names
    final browserMap = {
      'chrome': 'chromium',
      'firefox': 'firefox',
      'safari': 'webkit'
    };

    // Get the internal browser name
    final registryBrowserName =
        browserMap[requestedBrowser.toLowerCase()] ?? requestedBrowser;

    print('Mapping browser request: $requestedBrowser -> $registryBrowserName');

    final descriptors =
        _createBrowserDescriptors(browsersJson, registryBrowserName);

    final executables = descriptors
        .map((desc) => _createExecutableStatic(desc, registryDir))
        .where((e) => e != null)
        .cast<Executable>()
        .toList();

    return Registry._(
      registryDir: registryDir,
      descriptors: descriptors,
      executables: executables,
    );
  }

  static List<BrowserDescriptor> _createBrowserDescriptors(
    BrowserJson browsersJson,
    String browserName,
  ) {
    final entry = browsersJson.browsers.firstWhere(
      (b) => b.name == browserName,
      orElse: () => BrowserEntry(
        name: browserName,
        // Use specific revision instead of 'latest'
        revision: '1471',
        // Firefox's current revision from browsers.json
        browserVersion: '134.0',
        installByDefault: true,
        revisionOverrides: null,
      ),
    );

    return [_createDescriptorFromEntry(entry)];
  }

  static BrowserDescriptor _createDescriptorFromEntry(BrowserEntry entry) {
    final platformId = PlatformInfo.platformId;
    final revision = entry.revisionOverrides?[platformId] ?? entry.revision;

    return BrowserDescriptor(
        name: entry.name,
        browserName: entry.name.split('-')[0],
        revision: revision,
        hasRevisionOverride: entry.revisionOverrides?[platformId] != null,
        browserVersion: entry.browserVersion,
        installByDefault: entry.installByDefault,
        dir: BrowserPaths.getBrowserInstallDirectory(entry.name, revision));
  }

  static Future<void> _initializeExecutable(
    BrowserDescriptor descriptor,
    InstallationLock lock,
  ) async {
    try {
      await InstallationValidator.validateDependencies(descriptor.dir);
      await InstallationValidator.markInstalled(descriptor.dir);
    } finally {
      await lock.release();
    }
  }

  static Future<void> _downloadAndExtractStatic(
    String url,
    BrowserDescriptor descriptor,
    String registryDir,
  ) async {
    final lock = InstallationLock(registryDir);
    await lock.acquire();

    try {
      final tempFile = File('${descriptor.dir}.tmp');
      await BrowserDownloader.downloadWithProgress(
        url,
        tempFile.path,
        onProgress: (progress) {
          stdout.write('\r${progress.toString().padRight(60)}');
        },
      );

      final bytes = await tempFile.readAsBytes();
      await tempFile.delete();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final archiveFile in archive) {
        final filename = archiveFile.name;
        if (archiveFile.isFile) {
          final data = archiveFile.content as List<int>;
          final extractedFile = File(path.join(descriptor.dir, filename));
          await extractedFile.create(recursive: true);
          await extractedFile.writeAsBytes(data);
        }
      }

      if (!Platform.isWindows) {
        final executablePath = path.join(
          descriptor.dir,
          BrowserPaths.getExecutablePath(descriptor.name),
        );

        //verify binary exists
        if (!File(executablePath).existsSync()) {
          throw BrowserException(
              'Browser ${descriptor.name} is not installed. Run installation command.');
        }
        await Process.run('chmod', ['+x', executablePath]);
      }

      await _initializeExecutable(descriptor, lock);
    } catch (e) {
      await lock.release();
      rethrow;
    }
  }

  static List<String> _getDownloadUrlsStatic(BrowserDescriptor descriptor) {
    final paths = BrowserPaths.downloadPaths[descriptor.name];
    if (paths == null) return [];

    final template = paths[PlatformInfo.platformId];
    if (template == null) return [];

    final downloadPath = template.replaceAll('%s', descriptor.revision);
    return BrowserPaths.cdnMirrors
        .map((mirror) => '$mirror/$downloadPath')
        .toList();
  }

  List<Executable> get executables => List.unmodifiable(_executables);

  List<Executable> get defaultExecutables => _executables
      .where((e) => e.installType == InstallType.downloadByDefault)
      .toList();

  Executable? getExecutable(String name) {
    try {
      return _executables.firstWhere((e) => e.name == name);
    } catch (_) {
      return null;
    }
  }

  Future<void> validateRequirements(
    List<Executable> executables,
    String sdkLanguage,
  ) async {
    for (final executable in executables) {
      await executable.validateHostRequirements(sdkLanguage);
    }
  }

  Future<void> installExecutables(
    List<Executable> executables, {
    bool force = false,
  }) async {
    for (final executable in executables) {
      if (executable.install == null) {
        throw BrowserException(
            'Installation not supported for ${executable.name}');
      }
      await executable.install!();
    }
  }
}
