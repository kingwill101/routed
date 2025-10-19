import 'dart:io';
// For potential future use

/// Enumerates the high-level operating system platforms relevant for browser testing.
enum BrowserPlatform { linux, mac, win }

/// Provides detailed platform information relevant for selecting appropriate
/// browser binary downloads. Distinguishes between OS versions and architectures.
///
/// This class attempts to identify the operating system, version, and architecture
/// to generate platform identifiers compatible with Playwright's download structure.
class PlatformInfo {
  // Cache the computed values to avoid repeated process calls
  static String? _cachedPlatformId;
  static String? _cachedArchitecture;
  static BrowserPlatform? _cachedCurrentPlatform;

  /// Gets the high-level [BrowserPlatform] enum value for the current operating system.
  ///
  /// Throws [UnsupportedError] if the platform is not Linux, macOS, or Windows.
  static BrowserPlatform get currentPlatform {
    if (_cachedCurrentPlatform != null) return _cachedCurrentPlatform!;

    if (Platform.isLinux) return _cachedCurrentPlatform = BrowserPlatform.linux;
    if (Platform.isMacOS) return _cachedCurrentPlatform = BrowserPlatform.mac;
    if (Platform.isWindows) return _cachedCurrentPlatform = BrowserPlatform.win;
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Gets the specific platform identifier string used for browser downloads.
  ///
  /// This identifier typically includes OS, version, and architecture information,
  /// matching the keys used in Playwright's download infrastructure
  /// (e.g., 'ubuntu22.04-x64', 'mac13-arm64', 'win64').
  /// See [_getLinuxPlatformId] and [_getMacPlatformId] for details.
  /// Throws [UnsupportedError] for unsupported platforms.
  static String get platformId {
    if (_cachedPlatformId != null) return _cachedPlatformId!;

    try {
      final platform = currentPlatform; // Trigger enum resolution first
      final architecture = _getArchitecture(); // Determine architecture

      switch (platform) {
        case BrowserPlatform.linux:
          _cachedPlatformId = _getLinuxPlatformId(architecture);
          break;
        case BrowserPlatform.mac:
          _cachedPlatformId = _getMacPlatformId(architecture);
          break;
        case BrowserPlatform.win:
          // Playwright uses 'win64' for both x64 and arm64 Windows downloads.
          _cachedPlatformId = 'win64';
          break;
      }
      print("Detected platformId: $_cachedPlatformId");
      return _cachedPlatformId!;
    } catch (e) {
      // Propagate errors from underlying detection methods
      print("Error detecting platformId: $e");
      throw UnsupportedError(
        'Failed to determine platform identifier for ${Platform.operatingSystem}: $e',
      );
    }
  }

  /// Determines the specific Linux platform identifier (e.g., 'ubuntu22.04-x64').
  /// Attempts to read /etc/os-release, then falls back to lsb_release.
  /// Defaults to a compatible Ubuntu version if specific detection fails.
  static String _getLinuxPlatformId(String architecture) {
    // Try /etc/os-release first (more standard)
    try {
      final osReleaseContent = File('/etc/os-release').readAsStringSync();
      final properties = <String, String>{};
      for (final line in osReleaseContent.split('\n')) {
        final parts = line.split('=');
        if (parts.length == 2) {
          final key = parts[0].trim();
          // Remove quotes from value if present
          final value = parts[1].trim().replaceAll('"', '').replaceAll("'", '');
          properties[key] = value;
        }
      }

      final id = properties['ID']?.toLowerCase();
      final versionId = properties['VERSION_ID']?.toLowerCase();

      if (id != null && versionId != null) {
        if (id == 'ubuntu') {
          if (versionId.startsWith('24.04')) return 'ubuntu24.04-$architecture';
          if (versionId.startsWith('22.04')) return 'ubuntu22.04-$architecture';
          if (versionId.startsWith('20.04')) return 'ubuntu20.04-$architecture';
          // Add older versions if needed
        } else if (id == 'debian') {
          if (versionId.startsWith('12')) return 'debian12-$architecture';
          if (versionId.startsWith('11')) return 'debian11-$architecture';
          // Add older versions if needed
        }
        // Add mappings for other distributions based on Playwright's DOWNLOAD_PATHS if necessary
        print(
          "Detected Linux distro '$id' version '$versionId' from /etc/os-release.",
        );
      }
    } catch (e) {
      print("Could not read or parse /etc/os-release: $e. Trying lsb_release.");
      // Fall through to lsb_release
    }

    try {
      final idResult = Process.runSync('lsb_release', ['-is']);
      final versionResult = Process.runSync('lsb_release', ['-rs']);

      if (idResult.exitCode == 0 && versionResult.exitCode == 0) {
        final id = idResult.stdout.toString().toLowerCase().trim();
        final versionId = versionResult.stdout.toString().toLowerCase().trim();

        if (id == 'ubuntu') {
          if (versionId.startsWith('24.04')) return 'ubuntu24.04-$architecture';
          if (versionId.startsWith('22.04')) return 'ubuntu22.04-$architecture';
          if (versionId.startsWith('20.04')) return 'ubuntu20.04-$architecture';
        } else if (id == 'debian') {
          if (versionId.startsWith('12')) return 'debian12-$architecture';
          if (versionId.startsWith('11')) return 'debian11-$architecture';
        }
        print(
          "Detected Linux distro '$id' version '$versionId' from lsb_release.",
        );
      }
    } catch (e) {
      print("lsb_release command failed or not found: $e. Using fallback.");
      // Fall through to default
    }

    // Fallback if specific detection failed
    print(
      "Warning: Could not reliably determine specific Linux distribution and version. Using fallback 'ubuntu22.04-$architecture'. Compatibility not guaranteed.",
    );
    return 'ubuntu22.04-$architecture';
  }

  /// Determines the specific macOS platform identifier (e.g., 'mac13-arm64').
  /// Uses `sw_vers` for version and `uname -m` for architecture.
  static String _getMacPlatformId(String architecture) {
    try {
      final result = Process.runSync('sw_vers', ['-productVersion']);
      if (result.exitCode == 0) {
        final versionString = result.stdout.toString().trim();
        final versionParts = versionString.split('.');
        if (versionParts.isNotEmpty) {
          final majorVersion = int.tryParse(versionParts[0]);
          if (majorVersion != null) {
            // Map major OS version to Playwright's identifier scheme
            // Add newer versions as Playwright adds support
            if (majorVersion >= 15) {
              return 'mac15-$architecture'; // Assuming future support
            }
            if (majorVersion == 14) return 'mac14-$architecture';
            if (majorVersion == 13) return 'mac13-$architecture';
            if (majorVersion == 12) return 'mac12-$architecture';
            if (majorVersion == 11) return 'mac11-$architecture';
          }
        }
      }
    } catch (e) {
      print(
        "Could not execute sw_vers to determine macOS version: $e. Using fallback.",
      );
    }

    // Fallback based on potentially less reliable Platform info if sw_vers fails
    print(
      "Warning: Using fallback macOS version detection. Accuracy may vary.",
    );
    final version = Platform.operatingSystemVersion; // Less reliable parsing
    if (version.contains('14.')) return 'mac14-$architecture';
    if (version.contains('13.')) return 'mac13-$architecture';
    if (version.contains('12.')) return 'mac12-$architecture';
    if (version.contains('11.')) return 'mac11-$architecture';

    // Default to a recent version as a final fallback
    print(
      "Warning: Could not determine specific macOS version. Defaulting to 'mac14-$architecture'.",
    );
    return 'mac14-$architecture';
  }

  /// Gets the CPU architecture identifier ('arm64' or 'x64') using `uname -m`.
  static String _getArchitecture() {
    if (_cachedArchitecture != null) return _cachedArchitecture!;

    if (Platform.isWindows) {
      // Windows architecture detection is slightly different, but Playwright often uses 'win64' regardless.
      // Check environment variable for more detail if needed in the future.
      // final envArch = Platform.environment['PROCESSOR_ARCHITECTURE'];
      // if (envArch?.toUpperCase() == 'ARM64') return _cachedArchitecture = 'arm64';
      return _cachedArchitecture = 'x64'; // Assume x64 for win64 downloads
    }

    // For Linux and macOS
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        final machine = result.stdout.toString().trim().toLowerCase();
        if (machine == 'aarch64' || machine == 'arm64') {
          return _cachedArchitecture = 'arm64';
        }
        if (machine == 'x86_64') {
          return _cachedArchitecture = 'x64';
        }
      }
      print(
        "Warning: 'uname -m' failed or returned unexpected value (${result.stdout}). Falling back to Platform.version check.",
      );
    } catch (e) {
      print(
        "Warning: Could not execute 'uname -m': $e. Falling back to Platform.version check.",
      );
    }

    // Fallback using Platform.version (less reliable)
    final versionString = Platform.version.toLowerCase();
    if (versionString.contains('arm64') || versionString.contains('aarch64')) {
      return _cachedArchitecture = 'arm64';
    }
    return _cachedArchitecture = 'x64'; // Default assumption
  }
}
