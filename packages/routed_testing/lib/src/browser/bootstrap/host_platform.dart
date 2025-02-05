import 'dart:io';

class HostPlatform {
  static String get platform {
    if (Platform.isLinux) return _detectLinuxPlatform();
    if (Platform.isMacOS) return _detectMacPlatform();
    if (Platform.isWindows) return 'win64';
    throw Exception('Unsupported platform: ${Platform.operatingSystem}');
  }

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

  static bool get isOfficiallySupportedPlatform {
    try {
      platform;
      return true;
    } catch (_) {
      return false;
    }
  }
}
