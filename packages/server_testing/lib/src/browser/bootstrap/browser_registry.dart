import 'package:http/http.dart' as http;
import 'package:server_testing/src/browser/bootstrap/browser_installation.dart';
import 'package:server_testing/src/browser/browser_exception.dart';
import 'package:yaml/yaml.dart';

/// Fetches available browser installation details from a remote registry file.
///
/// This implementation assumes a specific YAML format hosted at a GitHub URL.
class BrowserRegistry {
  // TODO: Update this URL to the correct location of the browsers.yaml registry.
  /// The URL of the YAML file defining available browser versions and installations.
  static const String _registryUrl =
      'https://raw.githubusercontent.com/your-org/browser-registry/main/browsers.yaml';

      /// Fetches and parses the browser registry YAML file from the [_registryUrl].
      ///
      /// Returns a map where keys are browser names (e.g., 'chrome', 'firefox')
      /// and values are lists of available [BrowserInstallation] objects, typically
      /// sorted with the latest version first.
      ///
      /// Throws a [BrowserException] if the registry cannot be fetched or parsed.
  static Future<Map<String, List<BrowserInstallation>>>
      fetchAvailableBrowsers() async {
    final response = await http.get(Uri.parse(_registryUrl));
    if (response.statusCode != 200) {
      throw BrowserException('Failed to fetch browser registry',
          'HTTP ${response.statusCode}: ${response.body}');
    }

    final yaml = loadYaml(response.body) as YamlMap;
    final browsers = <String, List<BrowserInstallation>>{};

    for (var entry in yaml.entries) {
      final name = entry.key as String;
      final versions = entry.value as YamlList;
      browsers[name] = versions
          .map((v) => BrowserInstallation.fromYaml(name, v as YamlMap))
          .toList();
    }

    return browsers;
  }
}
