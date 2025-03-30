import 'package:server_testing/src/browser/bootstrap/version.dart';
import 'package:yaml/yaml.dart';

/// Represents metadata for a specific downloadable browser installation version.
///
/// Contains details like version number, revision, download URL, checksum,
/// and the expected executable path within the installed archive.
class BrowserInstallation {
  /// The name of the browser (e.g., 'chrome', 'firefox').
  final String name;
  /// The semantic version of the browser.
  final Version version;
  /// The specific build revision identifier for this download.
  final String revision;
  /// The checksum (e.g., SHA1, SHA256) for verifying the downloaded file.
  final String checksum;
  /// The direct URL to download the browser archive.
  final String downloadUrl;
  /// The relative path to the main executable within the downloaded archive.
  final String executablePath;

  /// Creates a browser installation metadata object.
  BrowserInstallation({
    required this.name,
    required this.version,
    required this.revision,
    required this.checksum,
    required this.downloadUrl,
    required this.executablePath,
  });

  /// Creates a [BrowserInstallation] instance by parsing data from a [YamlMap].
  ///
  /// Used when loading installation details from a registry file (e.g., `browsers.yaml`).
  /// Expects keys like `version`, `revision`, `checksum`, `download_url`,
  /// and `executable_path`.
  factory BrowserInstallation.fromYaml(String name, YamlMap data) {
    return BrowserInstallation(
      name: name,
      version: Version.parse(data['version'] as String),
      revision: data['revision'] as String,
      checksum: data['checksum'] as String,
      downloadUrl: data['download_url'] as String,
      executablePath: data['executable_path'] as String,
    );
  }
}
