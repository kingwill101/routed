import 'package:routed_testing/src/browser/bootstrap/version.dart';
import 'package:yaml/yaml.dart';

class BrowserInstallation {
  final String name;
  final Version version;
  final String revision;
  final String checksum;
  final String downloadUrl;
  final String executablePath;

  BrowserInstallation({
    required this.name,
    required this.version,
    required this.revision,
    required this.checksum,
    required this.downloadUrl,
    required this.executablePath,
  });

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
