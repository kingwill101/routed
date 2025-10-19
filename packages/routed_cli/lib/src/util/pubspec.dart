import 'package:file/file.dart' as fs;

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<String?> readPackageName(fs.Directory projectRoot) async {
  final pubspecFile = projectRoot.fileSystem.file(
    p.join(projectRoot.path, 'pubspec.yaml'),
  );
  if (!await pubspecFile.exists()) {
    return null;
  }
  try {
    final doc = loadYaml(await pubspecFile.readAsString());
    if (doc is YamlMap) {
      final name = doc['name'];
      if (name is String) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
  } catch (_) {
    // Ignore parse errors; caller will handle fallback behaviour.
  }
  return null;
}
