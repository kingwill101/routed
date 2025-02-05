import 'package:http/http.dart' as http;
import 'package:routed_testing/src/browser/bootstrap/browser_installation.dart';
import 'package:routed_testing/src/browser/browser_exception.dart';
import 'package:yaml/yaml.dart';

class BrowserRegistry {
  static const String _registryUrl =
      'https://raw.githubusercontent.com/your-org/browser-registry/main/browsers.yaml';

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
