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

/// Helper function to create an [Executable] instance from a [BrowserDescriptor].
///
/// Populates the [Executable] fields based on the descriptor, including
/// calculating paths, download URLs, and defining install/validation logic.
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

/// Helper function to download and install an executable described by [descriptor].
///
/// Uses the provided [urls] or generates them if empty. Iterates through mirror
/// URLs, attempts download and extraction using [_downloadAndExtractStatic].
/// Throws [BrowserException] if all download attempts fail.
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

/// Manages the discovery, installation, and validation of browser executables
/// based on a configuration source (like `browsers.json`).
///
/// Provides access to [BrowserDescriptor]s and [Executable] objects, handling
/// platform-specific details, download URLs, installation paths, and locking.
class Registry {
  /// The root directory where browsers are installed and managed.
  final String registryDir;
  /// A list of resolved [BrowserDescriptor]s relevant for the current platform
  /// and the requested browser.
  final List<BrowserDescriptor> descriptors;
  /// The internal list of [Executable] objects created from the descriptors.
  final List<Executable> _executables;

  /// Internal constructor for creating a [Registry] instance.
  Registry._({
    required this.registryDir,
    required this.descriptors,
    required List<Executable> executables,
  }) : _executables = executables;

  /// Creates and initializes a [Registry] instance.
  ///
  /// Processes the provided [browsersJson] data, determines the appropriate
  /// registry directory using [BrowserPaths.getRegistryDirectory], maps the
  /// [requestedBrowser] name to its internal registry name (e.g., 'chrome' -> 'chromium'),
  /// creates relevant [BrowserDescriptor]s using [_createBrowserDescriptors],
  /// and generates corresponding [Executable] objects using [_createExecutableStatic].
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

  /// Creates a list of [BrowserDescriptor]s relevant for the requested [browserName]
  /// based on the entries in [browsersJson].
  ///
  /// Finds the corresponding [BrowserEntry] and uses [_createDescriptorFromEntry]
  /// to resolve platform-specific details. Currently creates only one descriptor.
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

  /// Creates a single [BrowserDescriptor] from a [BrowserEntry].
  ///
  /// Resolves the correct revision number based on the current platform ID
  /// ([PlatformInfo.platformId]) and any overrides defined in the entry's
  /// `revisionOverrides`. Calculates the final installation directory path.
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

  /// Performs post-extraction initialization for a browser installation.
  ///
  /// Validates system dependencies using [InstallationValidator.validateDependencies],
  /// marks the installation as complete using [InstallationValidator.markInstalled],
  /// and releases the installation [lock].
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

  /// Downloads an archive from [url], extracts it into the target directory
  /// specified by the [descriptor] within the main [registryDir], and performs
  /// initialization using [_initializeExecutable].
  ///
  /// Acquires an [InstallationLock] before proceeding and releases it afterwards.
  /// Uses [BrowserDownloader] for the download and handles ZIP extraction and
  /// permission setting.
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

  /// Generates a list of potential download URLs for the given [descriptor].
  ///
  /// Uses [BrowserPaths.downloadPaths] and [BrowserPaths.cdnMirrors] to construct
  /// URLs based on the descriptor's name, revision, and the current platform ID.
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

  /// Returns an unmodifiable list of all known [Executable]s derived from the
  /// loaded configuration and relevant to the current platform.
  List<Executable> get executables => List.unmodifiable(_executables);

  /// Returns a list of [Executable]s that are marked for installation by default
  /// ([InstallType.downloadByDefault]).
  List<Executable> get defaultExecutables => _executables
      .where((e) => e.installType == InstallType.downloadByDefault)
      .toList();

      /// Gets the specific [Executable] instance identified by its [name].
      ///
      /// Returns `null` if no executable with the given name is found in the registry.
  Executable? getExecutable(String name) {
    try {
      return _executables.firstWhere((e) => e.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Validates platform-specific host requirements for each executable in the
  /// provided list of [executables].
  ///
  /// The [sdkLanguage] parameter provides context, potentially for error messages.
  /// Delegates to each executable's `validateHostRequirements` method.
  Future<void> validateRequirements(
    List<Executable> executables,
    String sdkLanguage,
  ) async {
    for (final executable in executables) {
      await executable.validateHostRequirements(sdkLanguage);
    }
  }

  /// Installs the specified list of [executables].
  ///
  /// Iterates through the list and calls the `install` method of each executable,
  /// if defined. Set [force] to true to potentially trigger reinstallation logic
  /// within the `install` method (depending on its implementation).
  /// Throws [BrowserException] if installation is not supported for an executable.
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
