import 'dart:io';

/// Provides information about the host operating system platform, specifically
/// tailored for determining compatibility and download paths for browser testing tools.
class HostPlatform {
  /// Gets the specific platform identifier string used for browser downloads.
  ///
  /// Examples: 'ubuntu20.04-x64', 'ubuntu22.04-x64', 'mac13-arm64', 'win64'.
  /// Attempts to detect Linux distribution and version using `lsb_release`.
  /// Detects macOS version and architecture.
  /// Throws an exception for unsupported platforms or Linux distributions.
  static String get platform {
    if (Platform.isLinux) return _detectLinuxPlatform();
    if (Platform.isMacOS) return _detectMacPlatform();
    if (Platform.isWindows) return 'win64';
    throw Exception('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Detects the specific Linux distribution and version using `lsb_release`.
  ///
  /// Returns a platform identifier string like 'ubuntu20.04-x64' or 'debian11-x64'.
  /// Throws an exception if `lsb_release` fails or the distribution/version
  /// is not supported.
  static String _detectLinuxPlatform() {
    // Use lsb_release to detect distribution and version
    final result = Process.runSync('lsb_release', ['-a']);
    final output = result.stdout.toString();

    String? distro;
    String? version;

    for (final line in output.split('\n')) {
      if (line.startsWith('Distributor ID:')) {
        distro = line.split(':')[1].trim().toLowerCase();
      }
      if (line.startsWith('Release:')) {
        version = line.split(':')[1].trim();
      }
    }

    if (distro == 'ubuntu') {
      if (version?.startsWith('20.04') ?? false) return 'ubuntu20.04-x64';
      if (version?.startsWith('22.04') ?? false) return 'ubuntu22.04-x64';
      if (version?.startsWith('24.04') ?? false) return 'ubuntu24.04-x64';
    }

    if (distro == 'debian') {
      if (version?.startsWith('11') ?? false) return 'debian11-x64';
      if (version?.startsWith('12') ?? false) return 'debian12-x64';
    }

    throw Exception('Unsupported Linux distribution: $distro $version');
  }

  /// Detects the specific macOS version (major) and architecture (x64 or arm64).
  ///
  /// Returns a platform identifier string like 'mac11', 'mac11-arm64', 'mac13'.
  /// Throws an exception if the macOS version is not recognized or supported.
  static String _detectMacPlatform() {
    final version = Platform.operatingSystemVersion;
    final isArm = Platform.version.contains('arm');

    if (version.contains('Version 10.15')) return 'mac10.15';
    if (version.contains('Version 11')) {
      return isArm ? 'mac11-arm64' : 'mac11';
    }
    if (version.contains('Version 12')) {
      return isArm ? 'mac12-arm64' : 'mac12';
    }
    if (version.contains('Version 13')) {
      return isArm ? 'mac13-arm64' : 'mac13';
    }

    throw Exception('Unsupported macOS version: $version');
  }

  /// Whether the current host platform is recognized and officially supported
  /// for browser downloads by this package.
  ///
  /// Checks if the [platform] getter executes without throwing an exception.
  static bool get isOfficiallySupportedPlatform {
    try {
      platform;
      return true;
    } catch (_) {
      return false;
    }
  }
}
