import 'dart:io';

enum BrowserPlatform {
  linux,
  mac,
  win,
}

class PlatformInfo {
  static BrowserPlatform get currentPlatform {
    if (Platform.isLinux) return BrowserPlatform.linux;
    if (Platform.isMacOS) return BrowserPlatform.mac;
    if (Platform.isWindows) return BrowserPlatform.win;
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

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

  static String _getLinuxPlatform() {
    final arch = _getArchitecture();
    
    // First try distribution-specific detection
    try {
      final result = Process.runSync('lsb_release', ['-is', '-rs']);
      final distro = result.stdout.toString().toLowerCase().trim();
      final version = result.stdout.toString().trim();

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
      return 'ubuntu22.04-$arch';  // Use Ubuntu build for Arch-based
    }
    if (_hasCommand('dnf') || _hasCommand('yum')) {
      // RedHat family: Fedora, CentOS, etc.
      return 'ubuntu22.04-$arch';  // Use Ubuntu build for RedHat-based
    }
    if (_hasCommand('zypper')) {
      // SUSE family
      return 'ubuntu22.04-$arch';  // Use Ubuntu build for SUSE-based
    }

    // Default to most compatible platform
    return 'ubuntu22.04-$arch';
  }

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

  static String _getArchitecture() {
    return Platform.version.contains('arm') ? 'arm64' : 'x64';
  }

  static bool _hasCommand(String command) {
    try {
      final result = Process.runSync('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}