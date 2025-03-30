import 'dart:io';

/// Enumerates the high-level operating system platforms relevant for browser testing.
enum BrowserPlatform {
  linux,
  mac,
  win,
}

/// Provides detailed platform information relevant for selecting appropriate
/// browser binary downloads. Distinguishes between OS versions and architectures.
class PlatformInfo {
  /// Gets the high-level [BrowserPlatform] enum value for the current operating system.
  ///
  /// Throws [UnsupportedError] if the platform is not Linux, macOS, or Windows.
  static BrowserPlatform get currentPlatform {
    if (Platform.isLinux) return BrowserPlatform.linux;
    if (Platform.isMacOS) return BrowserPlatform.mac;
    if (Platform.isWindows) return BrowserPlatform.win;
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Gets the specific platform identifier string used for browser downloads.
  ///
  /// This identifier typically includes OS, version, and architecture information,
  /// matching the keys used in Playwright's download infrastructure
  /// (e.g., 'ubuntu22.04-x64', 'mac13-arm64', 'win64').
  /// See [_getLinuxPlatform] and [_getMacPlatform] for details.
  /// Throws [UnsupportedError] for unsupported platforms.
  static String get platformId {
    if (Platform.isLinux) {
      return _getLinuxPlatform();
    }
    if (Platform.isMacOS) {
      return _getMacPlatform();
    }
    if (Platform.isWindows) {
      return 'win64';
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Determines the specific Linux platform identifier.
  ///
  /// Attempts to use `lsb_release` to identify Debian/Ubuntu versions.
  /// Falls back to checking for common package managers (`pacman`, `dnf`, `yum`, `zypper`)
  /// to infer distribution family and defaults to a reasonably compatible identifier
  /// (currently 'ubuntu22.04-x64' or 'ubuntu22.04-arm64'). Includes architecture.
  static String _getLinuxPlatform() {
    final arch = _getArchitecture();

    // First try distribution-specific detection
    try {
      final result = Process.runSync('lsb_release', ['-is', '-rs']);
      final distro = result.stdout.toString().toLowerCase().trim();
      // final version = result.stdout.toString().trim();

      // Map known distributions to compatible platforms
      if (distro.contains('debian')) {
        return 'debian12-$arch';
      }
      if (distro.contains('ubuntu')) {
        return 'ubuntu22.04-$arch';
      }
    } catch (_) {
      // LSB release detection failed, try alternative methods
    }

    // Check for common package managers to determine distribution family
    if (_hasCommand('pacman')) {
      // Arch-based: Manjaro, Arch, etc.
      return 'ubuntu22.04-$arch'; // Use Ubuntu build for Arch-based
    }
    if (_hasCommand('dnf') || _hasCommand('yum')) {
      // RedHat family: Fedora, CentOS, etc.
      return 'ubuntu22.04-$arch'; // Use Ubuntu build for RedHat-based
    }
    if (_hasCommand('zypper')) {
      // SUSE family
      return 'ubuntu22.04-$arch'; // Use Ubuntu build for SUSE-based
    }

    // Default to most compatible platform
    return 'ubuntu22.04-$arch';
  }

  /// Determines the specific macOS platform identifier based on OS version and architecture.
  ///
  /// Returns identifiers like 'mac11', 'mac11-arm64', 'mac12', 'mac12-arm64', 'mac13', 'mac13-arm64'.
  /// Defaults to 'mac13' or 'mac13-arm64' for unrecognized newer versions.
  static String _getMacPlatform() {
    final version = Platform.operatingSystemVersion;
    final isArm = Platform.version.contains('arm');

    if (version.contains('Version 13')) {
      return isArm ? 'mac13-arm64' : 'mac13';
    }
    if (version.contains('Version 12')) {
      return isArm ? 'mac12-arm64' : 'mac12';
    }
    if (version.contains('Version 11')) {
      return isArm ? 'mac11-arm64' : 'mac11';
    }

    return isArm ? 'mac13-arm64' : 'mac13';
  }

  /// Gets the CPU architecture identifier ('arm64' or 'x64').
  static String _getArchitecture() {
    return Platform.version.contains('arm') ? 'arm64' : 'x64';
  }

  /// Checks if a command-line [command] exists in the system's PATH.
  /// Uses `which` internally. Returns `false` if `which` fails or is not found.
  static bool _hasCommand(String command) {
    try {
      final result = Process.runSync('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
